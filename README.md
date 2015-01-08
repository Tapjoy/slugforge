slugforge
=========

## Contents ##
 - [Overview](#overview)
 - [Installation](#installation)
 - [Configuration](#configuration)
 - [Typical developer workflow](#typical-developer-workflow)
 - [Deploying slugs to production](#deploying-slugs-to-production)
 - [Repository format](#repository-format)
 - [The slug itself](#the-slug-itself)
 - [License](#license)
 - [Contributing](#contributing)

## Overview ##

Slugforge is a tool used at Tapjoy to build, manage, and deploy slugs of code for any project that
conforms to a basic structure defined below. The idea is to have a file that conforms to the "build"
part of a [12 factor app](http://12factor.net). We built this tool after looking at a number of
options in the open source community, but not finding anything that met all of our needs. After
building and using this tool over the past year we now want to share that work with the world so
that others can benefit for them as well.

A slug is a single file that contains all application code, build artifacts, and dependent binaries
necessary to run the application. This would include bundled gems for a ruby app, or jars for a java
app. As per the outlines laid out for a 12 factor app, the slug does not include any configuration
for the app. All configuration should be specified as environment variables, which the app should
recognize and which are specified outside of the slug. In practice the slug could be used to deploy
the application for a development, testing, qa, or production server, each of which only differ in
their configuration.

## Installation ##

Developers should install slugforge locally to assist with building, managing, and deploying slugs.
After following the installations below, you can confirm that slugforge is properly installed by
typing `slugforge` and ensuring that the help is displayed.

### Installing from source ###

If you are assisting with the development of Slugforge, or if the installation cannot be completed using the gem files
in Gemfury, you can clone the repositories and build the gems from their source.

1. Ensure that you are using an appropriate Ruby (like 1.9.3-p484), if necessary:

        rvm use 1.9.3-p484

1. Install the Tapjoy customized version of FPM:

        git clone git@github.com:Tapjoy/fpm.git
        cd fpm
        gem build fpm.gemspec
        gem install fpm*.gem --no-ri --no-rdoc
        cd ..

1. Install the slugforge gem:

        git clone git@github.com:Tapjoy/slugforge.git
        cd slugforge
        gem build slugforge.gemspec
        gem install slugforge*.gem --no-ri --no-rdoc
        cd ..

## Configuration ##

### Configuring settings ###

There are a few settings that need to be configured for certain functionality to be available. These can be configured in the environment, on the command-line, or in a configuration file.

#### AWS configuration ####

In order to store, retrieve, or query files in S3 buckets, or to be able to specify servers to deploy to by their instance ID, you need to configure your AWS access key and secret access key. As most developers will need these for other tools, we recommend setting the variables in your environment variables:

    export AWS_ACCESS_KEY_ID=<20 character access key>
    export AWS_SECRET_ACCESS_KEY=<40 character secret access key>

In addition to you AWS keys, Slugforge needs to know what bucket in S3 you will be using to store your slugs. This can be specified in your configuration file, environment, or on the command line:

* Slugforge configuration file

Add the following setting to your configuration file:

    aws:
      slug_bucket: <bucket_name>

* Environment variable:

        export SLUG_BUCKET=<bucket_name>

* Command-line parameter:

        --slug-bucket=<bucket_name>

#### SSH configuration ####

When deploying a slug to a host, the Slugforge tool with create a SSH connection to that host. It will first try a username
specified on the command line, or in your configuration files. If that is not specified, it will look at your standard SSH
configuration for a username. If all that fails, it will use your current username. If that account does not have access to
log into the remote host you should override the default:

    export SSH_USERNAME=<username>

## Typical developer workflow ##

Once a developer has finished making their changes and have tested them locally, they are generally
interested in deploying them to some test environment so that they can test them in a more production-like
environment. Slugforge helps automate that process, making it simple and repeatable.

### Build a slug with the command line tools ###

NOTE: If any gems are used that include native extensions, the slug must be built on the same
architecture as it will be deployed to.

In certain circumstances, it may be useful to build your slug locally. A local slug can generally be built from the
project's root directoy by running the following command:

    slugforge build --ruby 1.9.3-p194

This will create a new slug in the current directory. While specifying the ruby version is
optional, the above recommended value is currently appropriate in most cases.

### Tagging your slugs (recommended)

Slugs can be tagged with names, such as the deployment that they are associated with. To tag a
slug on S3 for `myproject` as `stable`, do the following:

    slugforge tag set stable <slug_name> --project myproject

You can tag any slug using a portion of its name. This can be any sequential subset of characters, as long as it uniquely identifies the slug. To tag a specific slug for the current project as `test`, do the following:

1. Determine the name of the slug

        slugforge wrangler list

1. Create the `test` tag for the slug using a unique portion of the slug name. Assuming that the slug name
was `myproject-20130909201513-8b81b614d3.slug`, you might use:

        slugforge tag set test 0909201513

### Deploying your slugs

Now that you have your slug, and have a way of referencing it, it's time to deploy your slug
for testing. The most convenient ways of deploying is by
tag. You can optionally pass a list of servers to deploy to, rather than a single
server. In addition, if you are in the local repository for a project, the `--project` option is
optional.

When specifying the hosts to a deploy to, there are a number of ways to target them. The different
types can be intermixed and will all be OR'ed together to determine the list of target machines:

* IP Addresses: four numbers, joined with dots (eg. 123.45.6.78)
* Host name: a series of words, joined with dots (eg. ec2-123-45-6-78.compute-1.amazonaws.com)
* EC2 instance: an AWS instance name (eg. i-0112358d)
* AWS tag: an AWS tag name and value, joined with equals (eg. cluster=watcher)
* Security group: an AWS security group name (eg. connect-19)

NOTE: When using instance names, tags, or security groups, you need to be
using an AWS access key and secret key that have permissions to view those
resources. This can create conflicts if the S3 bucket that you want to access
is using a different pair of keys.

#### Deploying by tag name ####

Assuming that you wanted to deploy the `stable` release of `myproject` to the host at
`12.13.14.15`, you would execute:

    slugforge deploy tag stable 12.13.14.15 --project myproject

#### Deploying local slug files ####

If you had built your slug locally, you can deploy the file directly from your local machine. To
deploy a file in the current directory called `filename.slug` to server `12.13.14.15`, and install
it as `myproject`, you would execute:

    slugforge deploy file filename.slug 12.13.14.15 --project myproject

## Repository format ##

The repository used to create a slug need only have a few required parts.

### Procfile ###

The slug will create upstart services when installing the slug based on the lines in the Procfile at
the root of the repository. This is exactly the same format as a Heroku/Foreman Procfile. Each line
will be converted to an upstart service which will monitor the lifecycle of each of the apps
processes.

### "build" script ###

The contents of the slug will be the entire repository directory contents, minus the `.git`, `log`,
and `tmp` directories, in whatever state its in after running a script found in `deploy/build`. This
script can be written in any language and perform any tasks but it should put the repository in the
necessary state for packaging such that all processes defined in the `Procfile` will run
successfully. That means that any binaries specified in the `Procfile` should be created, compiled,
downloaded, materialized, conjured etc. All dependent packages or binaries should be placed in the
repository. For example, a ruby project might want to call `bundle install --paths vendor/bundle` in
order to package all necessary gems for runtime execution.

If no `deploy/build` script exists in your repository, no prepackage build steps will be taken.

### Install behavior customization ###

If your slug requires extra fancy post install setup, you can configure that by adding scripts in
the `deploy` directory at the root of your repo. slugforge will look for a subset of the scripts run
by the [chef deploy_revision resource](http://docs.opscode.com/resource_deploy.html). It will run
`deploy/before_restart` and `deploy/after_restart` at the times you would expect when
originally starting or restarting the upstart services associated with the app.

This sort of customization should only be app specific and very minimal. All prerequisite OS
configuration and slug install should be managed by a tool like chef or puppet, or baked directly into the AMI.

## The slug itself ##

The slug will be a .slug package which contains the state of the app repo after the build script has
run as well as the upstart scripts generated by this tool.  That's it. El fin. The files will be
installed on the server in `/opt/apps/<app-name>` where app-name is configured at deploy time
defaulting to the name of the directory containing the repo.

### Slug storage ###

Slugs will be stored in S3 and downloaded to servers on deploy. The S3 bucket will have project
directories which contain the slugs for any given project. The name of the slug will follow the
format

    <project_name>-<build_time>-<partial_sha>.slug

For example

    project-20130714060000-5bcb55141b.slug

### Deploying ###

From a single server's point of view, in order to deploy a new slug to a server run the command

    curl http://s3.amazonaws.com/slugs/<project_name>/<slug_name>.slug && <slug_name>.slug -r -i <deploy_path>

The deploy scripts we use to deploy clusters will coordinate which slug is installed on each server
to allow for isolated deploys, incremental rollout, rollback etc. The most recently installed slugs
will be cached in /tmp on a server to allow for fast rollback.

On installation the upstart scripts will be installed in `/etc/init` and started or restarted.

### Unicorn/Rainbows support ###

Slugs have special handling for unicorn and rainbows to correctly handle the interactionb between upstart and
the rolling restart done by sending a USR2 signal to unicorn or rainbows, heretoafter referred to as unicorn.

#### What you need to know ####

Unicorn master will be managed correctly by upstart for start, stop and restart. However, in order for your app to
correctly handle the reload it needs the following in the unicorn.rb config file.

_NOTE_:

* After restart the new unicorn master must load all of the rails code. This can take a while and any code
changes will not be visible until it is done loading and has replaced the old master process.


This needs to be anywhere in the top scope of your config file.

    # Unicorn will respawn on signal USR2 with this command. By defaults its the same one it was
    # launched with. In capistrano style deploys this will always be the same revision
    # unless we explicitly point it to the 'current' symlink.
    Unicorn::HttpServer::START_CTX[0] = ::File.join(ENV['GEM_HOME'].gsub(/releases\/[^\/]+/, "current"),'bin','unicorn')

This needs to be the contents of your `before_exec` block. You can have additional config in `before_exec` but be
careful not to disrupt the logic here.

    before_exec do |server|
      # Read environment settings from .env. This allows the environment to be changed during a unicorn
      # upgrade via USR2. Remove leading "export " if its there
      env_file = File.join(app_dir, '.env')

      if File.exists?(env_file)
        File.foreach(env_file) do |line|
          name,value = line.split('=').map{ |v| v.strip }
          name.gsub!(/^export /,'')
          ENV[name]=value
        end
      end

      # In capistrano style deployments, the newly started unicorn master in no-downtime
      # restarts will get the GEM_HOME from the previous one.
      # By pointing it at the 'current' symlink we know we're up to date.
      # No effect in other types of deployments
      ENV['GEM_HOME'] = ENV['GEM_HOME'].gsub(/releases\/[^\/]+/, "current")

      # put the updated GEM_HOME bin in the path instead of the specific release directory
      # in capistrano like deployments
      paths = (ENV["PATH"] || "").split(File::PATH_SEPARATOR)
      paths.unshift ::File.join(ENV['GEM_HOME'], 'bin')
      ENV["PATH"] = paths.uniq.join(File::PATH_SEPARATOR)
    end

All of this is to tell unicorn to use the new location of the `current` symlink created by a new slug install instead of
the old target directory it was originally pointing to. It also will reread the `.env` file in the slug's top level
directory upon restart.

#### The details ####

If your Procfile has a line for either unicorn or rainbows it, upon installation the slug will export an upstart
service config file that doesn't start unicorn but starts a shell script called unicorn-shepherd.sh which is packaged in the slug.
This script stays alive and gives upstart a constant pid to monitor. The script starts unicorn and waits for the unicorn master
pid to die. If it receives a restart command from upstart it will send a USR2 signal to the unicorn master and exit. While unicorn
forks a new master and starts rolling new workers, upstart will restart the unicorn-shepherd.sh script which will find the
new master and wait for it.

## License ##

This software is released under the MIT license. See the `LICENSE` file in the repository for
additional details.

## Contributing ##

Tapjoy is not currently accepting contributions to this code at this time. We are in the process of
formalizing our Contributor License Agreement and will update this section with those details when
they are available.

## Thank You ##
Thank you to the entire engineering team at Tapjoy.  Including, but not limited to, @jjrussell, @andyleclair, @jlogsdon, @ofanite, and @ehealy.
