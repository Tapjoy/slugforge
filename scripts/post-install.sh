#!/bin/bash

# Environment variables can be used to modify the behavior of this script. They
# must be present in the environment of the slug when it is installed
#
# KILL_TIMEOUT - change the upstart kill timeout which is how long upstart will
#                wait upon stopping a service for child processes to die before
#                sending kill -9
# CONCURRENCY  - Concurrency used for foreman export. Same format as concurrency
#                argument passed for foreman
# RUNTIME_RUBY_VERSION - The ruby version to put in the upstart templates to run the service.
#                If specified 'rvm use $RUNTIME_RUBY_VERSION do' will prefix the process
#                command in the Procfile
# LOGROTATE_POSTROTATE - The shell code to run in the logrotate 'postrotate' stanza
#                        in the logrotate config file created for this slug's upstart
#                        service. Default is 'restart <servicename>'

set -e

SHARED_DIR="${INSTALL_ROOT}/shared"
# make shared folders, if needed
mkdir -p ${SHARED_DIR}/config

linked_dirs=(log pids tmp)

for d in ${linked_dirs[@]} ; do
    mkdir -p "${SHARED_DIR}/${d}"
    # create the symlinks for shared folders, if needed
    if [ ! -h "$INSTALL_DIR/${d}" ] ; then
        rm -rf "$INSTALL_DIR/${d}" # delete local copy, use shared
        ln -s -f "${SHARED_DIR}/${d}" "${INSTALL_DIR}/${d}"
    fi
done
chmod -R 775 ${SHARED_DIR}

# set owner for project tree
chown -R $OWNER ${INSTALL_ROOT}

# make sure all deploy scripts are executable
chmod +x ${INSTALL_DIR}/deploy/*

# if environment file exists, link it into current directory so DotEnv and foreman run work
if [ -r "${SHARED_DIR}/env" ] ; then
    ln -s -f "${SHARED_DIR}/env" "${INSTALL_DIR}/.env"
fi

# run post_install script, if present
if [ -r "${INSTALL_DIR}/deploy/post_install" ] ; then
    echo "Running post_install script..."
    su - $OWNER -c "${INSTALL_DIR}/deploy/post_install"
fi

if which service && which start && which stop > /dev/null 2>&1 ; then
    UPSTART_PRESENT=true
else
    UPSTART_PRESENT=false
fi

if $UPSTART_PRESENT ; then
    if [ -n "$CONCURRENCY" ] ; then
        CONCURRENCY="-c $CONCURRENCY"

	# split up the concurrency string into its parts and check each app to see if its
	# unicorn or rainbows. We can only have one at a time because if they share a pid
	# directory unicorn-upstart can't tell which process to watch.
	# e.g.
	# web=1,other=1 gets split on the command then app gets split on the = to be web and other
	FOUND_UNICORN=false
	for app in $(echo ${CONCURRENCY/,/ }) ; do
	    app=${app%=*}
	    if egrep -q "^${app}:.*(unicorn|rainbows)" "${INSTALL_DIR}/Procfile" ; then
		if $FOUND_UNICORN ; then
		    echo "The concurrency you have set of '$CONCURRENCY' will result in two unicorn or rainbows servers running at the same time. Slug deploys do not support that."
		    echo "Update your concurrency to only run one. You can deploy also this slug again in another directory with a different concurrency to run both simultaneously."
		    exit 1
		fi
		FOUND_UNICORN=true
	    fi
	done
    fi

    PROJECT_NAME=$(basename $INSTALL_ROOT)

    # upstart has problems with services with dashes in them
    PROJECT_NAME=${PROJECT_NAME/-/_}

    if [ -n "$RUNTIME_RUBY_VERSION" ] ; then
        # used inside the foreman template
        export RUBY_CMD="rvm use $RUNTIME_RUBY_VERSION do"
    elif [ -r "${INSTALL_DIR}/.ruby-version" ] ; then
        export RUBY_CMD="rvm use $(head -n 1 ${INSTALL_DIR}/.ruby-version) do"
    fi

    EXPORT_COMMAND="foreman export upstart /etc/init -a $PROJECT_NAME -f $INSTALL_DIR/Procfile -l $INSTALL_DIR/log $CONCURRENCY -t $INSTALL_DIR/deploy/upstart-templates -d $INSTALL_ROOT -u $OWNER"
    echo "Running foreman export command '$EXPORT_COMMAND'"
    $EXPORT_COMMAND

    # start or restart the service
    if status ${PROJECT_NAME} | grep -q running ; then
        # restart the service
        echo "Post install complete. Restarting ${PROJECT_NAME} service... "
        restart ${PROJECT_NAME}
    else
        # start the new service
        echo "Post install complete. Starting ${PROJECT_NAME} service... "
        start ${PROJECT_NAME}
    fi
else
    echo "This machine does not appear to have upstart installed so we're skipping"
    echo "exporting the upstart service config files."
fi

if [ -d "/etc/logrotate.d" ] ; then
    LOGROTATE_FILE="/etc/logrotate.d/${PROJECT_NAME}"
    LOG_DIR="${INSTALL_DIR}/log"
    echo "Installing logrotate config ${LOGROTATE_FILE}"
    : ${LOGROTATE_POSTROTATE:="restart ${PROJECT_NAME}"}
    cat <<EOF > "${LOGROTATE_FILE}"
${LOG_DIR}/*log ${LOG_DIR}/*/*.log {
    size=10G
    rotate 2
    missingok
    notifempty
    sharedscripts
    postrotate
        ${LOGROTATE_POSTROTATE}
    endscript
}

EOF
else
    echo "This machine does not appear to have logrotate installed so we're skipping"
    echo "log rotation config."
fi
