#!/bin/bash

# This script is a bridge between upstart and unicorn/rainbows, hereafter referred to as unicorn.
#
# The reason this is necessary is that upstart wants to start and watch a pid for its entire
# lifecycle. However, unicorn's cool no-downtime restart feature creates a new unicorn master
# which will create new workers and then kill the original master. This makes upstart think that
# unicorn died and it gets wonky from there.
#
# So this script is started by upstart. It can detect if a unicorn master is already running
# and will wait for it to exit.  Then upstart will restart this script which will see if
# a unicorn master is running again. On no-downtime restarts it will find the new unicorn master
# and wait on it to exit, and so on.  So unicorn is managing its own lifecycle and this script
# gives upstart a single pid to start and watch.
#
# This script also handles the signals sent by upstart to stop and restart and sends them to the
# running unicorn master to initiate a no-downtime restart when the upstart 'restart' command
# is given to this service.
#
# We do some crazy magic in is_restarting to determine if we are restarting or stopping.


#############################################################
##
## Set up environment
##
#############################################################

COMMAND=$1
SERVICE=$2

# logs to syslog with service name and the pid of this script
log() {
    # we have to send this to syslog ourselves instead of relying on whoever launched
    # us because the exit signal handler log output never shows up in the output stream
    # unless we do this explicitly
    echo "$@" | logger -t "${SERVICE}[$$]"
}

# assume upstart config cd's us into project root dir.
BASE_DIR=$PWD
LOG_DIR="${BASE_DIR}/log/unicorn"
TRY_RESTART=true

#############################################################
##
## Support functions
##
#############################################################

# Bail out if all is not well
check_environment(){
    if [ "x" = "x${COMMAND}" ] ; then
        log "Missing required argument: Command to launch unicorn or rainbows. [unicorn|rainbows]"
        exit 1
    fi

    if [ "x" = "x${SERVICE}" ] ; then
        log "Missing required second argument: Upstart service name that launched this script"
        exit 1
    fi

    if [ -r $BASE_DIR/config/unicorn.rb ] ; then
        CONFIG_FILE=$BASE_DIR/config/unicorn.rb
    elif  [ -r $BASE_DIR/config/rainbows.rb ] ; then
        CONFIG_FILE=$BASE_DIR/config/rainbows.rb
    else
        log "No unicorn or rainbows config file found in '$BASE_DIR/config'. Exiting"
        exit 1
    fi

    # default to RAILS_ENV if RACK_ENV isn't set
    export RACK_ENV="${RACK_ENV:-$RAILS_ENV}"

    if [ ! -n "$RACK_ENV" ] ; then
        log "Neither RACK_ENV nor RAILS_ENV environment variable are set. Exiting."
        exit 1
    fi

}

# Return the pid of the new master unicorn. If there are two master unicorns running, not
# a new one and one marked old which is exiting, but two that think they are the master
# then exit with an error. How could we handle this better? When would it happen?
# Delete any pid files found which have no corresponding running processes.
master_pid() {
    local pid=''
    local extra_pids=''
    local multi_master=false

    for PID_FILE in $(find $BASE_DIR/pids/ -name "*.pid") ; do
        local p=`cat ${PID_FILE}`

        if is_pid_running $p ; then
            if [ -n "$pid" ] ; then
                multi_master=true
                extra_pids="$extra_pids $p"
            else
                pid="$p"
            fi
        else
            log "Deleting ${COMMAND} pid file with no running process '$PID_FILE'"
            rm $PID_FILE 2> /dev/null  || log "Failed to delete pid file '$PID_FILE': $!"
        fi
    done
    if $multi_master ; then
        log "Found more than one not old ${COMMAND} master process running. Pids are '$pid $extra_pids'."
        log "Killing them all and restarting."
        kill -9 $pid $extra_pids
        exit 1
    fi

    echo $pid
    # return status so we can use this function to see if the master is running
    [ -n "$pid" ]
}

is_pid_running() {
    local pid=$1
    if [ ! -n "$pid" ] || ! [ -d "/proc/$pid" ] ; then
        return 1
    fi
    return 0
}


# output parent process id of argument
ppid() {
    ps -p $1 -o ppid=
}

free_mem() {
    free -m | grep "buffers/cache:" | awk '{print $4};'
}

# kills off workers whose master have died. This is indicated by a worker whose
# parent process is the init process.
kill_orphaned_workers() {
    local workers=`ps aux | egrep "${COMMAND}.*worker" | grep -v grep | awk '{print $2}'`
    for worker in $workers ; do
        # if the worker's parent process is init, its master is dead.
        if [ "1" = `ppid $worker` ] ; then
            log "Found ${COMMAND} worker process with no master. Killing $worker"
            kill -QUIT $worker
        fi
    done
}

# This is the on exit handler. It checks if we are restarting or not and either sends the USR2
# signal to unicorn or, if the service is being stopped, kill the unicorn master.
respawn_new_master() {
    # TRY_RESTART is set to false on exit where we didn't recieve TERM.
    # When we used "trap command TERM" it did not always trap propertly
    # but "trap command EXIT" runs command every time no matter why the script
    # ends. So we set this env var to false if we don't need to respawn which is if unicorn
    # dies by itself or is restarted externally, usually through the deploy script
    # or we never succesfully started it.
    # If we receive a TERM, like from upstart on stop/restart, this won't be set
    # and we'll send USR2 to restart unicorn.
    if $TRY_RESTART ; then
        if is_service_in_state "restart" ; then
            local pid=`master_pid`
            if [ -n "$pid" ] ; then
                # free memory before restart. Restart is unreliable with not enough memory.
                # New master crashes during startup etc.
                let min_mem=1500
                let workers_to_kill=8
                let count=0

                while [ `free_mem` -lt $min_mem ] && [ $count -lt $workers_to_kill ] ; do
                    log "Sending master ${pid} TTOU to drop workers to free up memory for restart"
                    kill -TTOU ${pid}
                    sleep 2
                    count=$((count + 1))
                done

                if [ `free_mem` -lt $min_mem ] ; then
                    log "Still not enough memory to restart. Killing the master and allowing upstart to restart."
                    kill -9 ${pid}
                else
                    # gracefully restart all current workers to free up RAM,
                    #   then respawn master
                    kill -USR2 ${pid}
                    log "Respawn signals HUP + USR2 sent to ${COMMAND} master ${pid}"
                fi
            else
                log "No ${COMMAND} master found. Exiting. A new one will launch when we are restarted."
            fi
        elif is_service_in_state "stop" ; then
            local pid=`master_pid`
            if [ -n "$pid" ] ; then
                tries=1
                while is_pid_running ${pid} && [ $tries -le 5 ] ; do
                    log "Service is STOPPING. Trying to kill '${COMMAND}' at pid '${pid}'. Try ${tries}"
                    kill ${pid}
                    tries=$(( $tries + 1 ))
                    sleep 1
                done

                if is_pid_running ${pid} ; then
                    log "Done waiting for '${COMMAND}' process '${pid}' to die. Killing for realz"
                    kill -9 ${pid}
                else
                    log "${COMMAND} process '${pid}' is dead."
                fi
            fi
        else
            log "Service is neither stopping nor restarting. Exiting."
        fi
    else
        log "Not checking for restart"
    fi
}

# Upstart does not have the concept of "restart". When you restart a service it is simply
# stopped and started. But this defeats the purpose of unicorn's USR2 no downtime trick.
# So we check the service states of the foreman exported services. If any of them are
# start/stopping or start/post-stop it means that they are stopping but that the service
# itself is still schedule to run. This means restart. We can use this to differentiate between
# restarting and stopping so we can signal unicorn to restart or actually kill it appropriately.
is_service_in_state() {
    local STATE=$1
    if [ "$STATE" = "restart" ] ; then
        PATTERN="(start/stopping|start/post-stop)"
    elif [ "$STATE" = "stop" ] ; then
        PATTERN="/stop"
    else
        log "is_service_in_state: State must be one of 'stop' or 'restart'. Got '${STATE}'"
        exit 1
    fi
    # the service that started us and the foreman parent services, pruning off everything
    # after each successive dash to find parent service
    # e.g. myservice-web-1 myservice-web myservice
    services=( ${SERVICE} ${SERVICE%-*} ${SERVICE%%-*} )

    IN_STATE=false

    for service in "${services[@]}" ; do
        if /sbin/status ${service} | egrep -q "${PATTERN}" ; then
            log "Service ${service} is in state '${STATE}'. - '$(/sbin/status ${service})'"
            IN_STATE=true
        fi
    done

    $IN_STATE # this is the return code for this function
}

#############################################################
##
## Trap incoming signals
##
#############################################################

# trap TERM which is what upstart uses to both stop and restart (stop/start)
trap "respawn_new_master" EXIT

#############################################################
##
## Main execution
##
#############################################################

check_environment

kill_orphaned_workers

if ! master_pid ; then

    # make sure it uses the 'currrent' symlink and not the actual path
    export BUNDLE_GEMFILE=${BASE_DIR}/Gemfile

    log "No ${COMMAND} master found. Launching new ${COMMAND} master in env '$RACK_ENV' in directory '$BASE_DIR', BUNDLE_GEMFILE=$BUNDLE_GEMFILE"

    mkdir -p "${LOG_DIR}"

    # setsid to start this process in a new session because when upstart stops or restarts
    # a service it kills the entire process group of the service and relaunches it. Because
    # we are managing the unicorn separately from upstart it needs to be in its own
    # session (group of process groups) so that it survives the original process group
    setsid bundle exec ${COMMAND} -E ${RACK_ENV} -c ${CONFIG_FILE} >> ${LOG_DIR}/unicorn.log 2>&1 &

    tries=1
    while [ $tries -le 10 ] && ! master_pid ; do
        log "Waiting for unicorn to launch master"
        tries=$(( $tries + 1 ))
        sleep 1
    done
fi

PID=`master_pid`

if is_pid_running $PID ; then
    # hang out while the unicorn process is alive. Once its gone we will exit
    # this script. When upstart respawns us we will end up in the if statement above
    # to relaunch a new unicorn master.
    log "Found running ${COMMAND} master $PID. Awaiting its demise..."
    while is_pid_running $PID ; do
        sleep 5
    done
    log "${COMMAND} master $PID has exited."
else
    log "Failed to start ${COMMAND} master. Will try again on respawn. Exiting"
fi

TRY_RESTART=false
