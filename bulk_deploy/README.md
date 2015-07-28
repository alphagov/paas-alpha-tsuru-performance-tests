Deploying Many Teams And Many Apps
==================================

This directory contains a script to deploy potentially a large amount of teams
and applications.

This script is based on [`rake`](http://docs.seattlerb.org/rake/) to group and
run all the tasks.

## How to execute

To execute this script, use bundle to install the dependencies
(use of [rvm](https://rvm.io/) or rbenv is recommended)

```
# rvm use --create 2.2.2@tsuru-performance-tests # optional
bundle install
```

And call rake:

```
bundle exec rake \
    admin_pass=mysecretpass \
    environment=test host=tsuru.paas.alphagov.co.uk \
    num_users=10 num_teams=2 \
    dm_api_pg_dump_url="http://somehost.com/full.dump" \
    dm_api_pg_dump_auth_header="Auth: ..." \
    deploy
```

To list all actions:

```
bundle exec rake \
    admin_pass=mysecretpass \
    environment=test host=tsuru.paas.alphagov.co.uk \
    num_users=10 num_teams=2 \
    dm_api_pg_dump_url="http://somehost.com/full.dump" \
    dm_api_pg_dump_auth_header="Auth: ..." \
    -T
```

See below for more details about actions

## Configuration

The script receives multiple parameters such as number of teams or number of
units per app. These parameters can pass as arguments as `var=value` or as environment
variables.

Check the top of the file `Rakefile` to learn about all the possible parameters.

The most important variables are:

  * **(required)** `environment=myenvname`: prefix of the environment
  * **(required)** `host=tsuru.paas.alphagov.co.uk`: Base domain for the environment
  * **(required)** `admin_user=...` and `admin_pass=...`: Credentials of admin user
  * **(required)** `dm_api_pg_dump_url=...` and `dm_api_pg_dump_auth_header=...`: Info to get postgress dump.
  * `num_teams`, `num_users`, `units_per_app`: Change this to change the size of the deployment.
  * `dm_api_token`, `dm_search_api_token` and `dm_search_api_url`: Specific config for datamarket apps.
  * `workdir`: Temporary directory for logs, data, tmp files. Default `/tmp/workdir`

## Actions

This is a `Rakefile` so you can list all the actions with `rake <options> -T`:

```
bundle exec rake \
    admin_user=... admin_pass=... \
    environment=myenv host=tsuru2.paas.alphagov.co.uk \
    num_users=10 num_teams=2 \
    dm_api_pg_dump_url=... \
    dm_api_pg_dump_auth_header=...
    -T
```

### Main actions

Deploys or removes all the environment.

 * `rake deploy  # Bring up all the environment`
 * `rake destroy # Bring down all the environment`


### Team an user creation

Will create all the teams and users with their keys and ssh wrappers for git push.

Properties:

 * The naming convention is : `bulkt<team_id>: bulkt1, bulkt2` and `user<userid>@<team>.site.com: user1@bulkt1.site.com`
 * Each user has one team.

```
rake teams:create_all                                      # Create all teams and its users
rake teams:remove_all                                      # Remove all teams and its users
rake teams:bulkt1:create                                   # Create team bulkt1
rake teams:bulkt1:remove                                   # Remove team bulkt1
rake teams:bulkt1:users:create_all                         # Create all users in team bulkt1
rake teams:bulkt1:users:remove_all                         # Remove all users in team bulkt1
rake teams:bulkt1:users:user1@bulkt1.site.com:create       # Create user user1@bulkt1.site.com in team bulkt1
rake teams:bulkt1:users:user1@bulkt1.site.com:remove       # Remove user user1@bulkt1.site.com in team bulkt1
```

### Repo cloning

Will clone the git repos of each app

```
rake clone:all                                             # Clone all repos
rake clone:clone_digitalmarketplace-admin-frontend         # Clone repository https://github.com/alphagov/multicloud-digitalmarketplace-admin-frontend for app digitalmarketp...
rake clone:clone_digitalmarketplace-api                    # Clone repository https://github.com/alphagov/multicloud-digitalmarketplace-api for app digitalmarketplace-api
rake clone:clone_digitalmarketplace-buyer-frontend         # Clone repository https://github.com/alphagov/multicloud-digitalmarketplace-buyer-frontend for app digitalmarketp...
rake clone:clone_digitalmarketplace-search-api             # Clone repository https://github.com/alphagov/multicloud-digitalmarketplace-search-api for app digitalmarketplace...
rake clone:clone_digitalmarketplace-supplier-frontend      # Clone repository https://github.com/alphagov/multicloud-digitalmarketplace-supplier-frontend for app digitalmark...
rake clone:clone_example-java-jetty                        # Clone repository https://github.com/alphagov/example-java-jetty for app example-java-jetty
rake clone:clone_flask-sqlalchemy-postgres-heroku-example  # Clone repository https://github.com/alphagov/flask-sqlalchemy-postgres-heroku-example for app flask-sqlalchemy-p...
```

### App deployment

Deploys the different apps. They are [rake parametrised tasks](https://robots.thoughtbot.com/how-to-use-arguments-in-a-rake-task)
which allow you set the team and the user to deploy the app.

By default, these 5 apps are deployed right now:

- example Java Jetty app
- example Flask app
- Digital Marketplace admin frontend app
- Digital Marketplace admin suppliers app
- Digital Marketplace admin buyers app

Digital Marketplace backend apps are not deployed yet, so frontend apps use preview environment.

In the future we want to improve this script to deploy our own DM backend apps without relying on the preview environment.

The application will follow this rules:

 * One app per team.
 * **Will not deploy** if the app is already deployed and running.
 * app name: `something-<teamname>`, e.g.: `flask-app-bulkt1`
 * service name `<teamname>-something-db`,  e.g.: `bulkt1-flask-db`


```
rake apps:flask-app:deploy[teamname,username]              # Deploy the flask-app
rake apps:flask-app:remove[teamname,username]              # Remove the flask-app

rake apps:java-app:deploy[teamname,username]               # Deploy the java-app
rake apps:java-app:remove[teamname,username]               # Remove the java-app

rake apps:dm-admin-frontend:deploy[teamname,username]      # Deploy Datamarket Admin frontend - dm-buyer-frontend
rake apps:dm-admin-frontend:remove[teamname,username]      # Remove Datamarket Admin frontend - dm-buyer-frontend

rake apps:dm-api:deploy                                    # Deploy Datamarket API and import DB - dm-api
rake apps:dm-api:deploy_app[teamname,username]             # Deploy Datamarket API (no db dump) - dm-api
rake apps:dm-api:import_pg_dump                            # Import Datamarket API postgres DB
rake apps:dm-api:remove[teamname,username]                 # Remove Datamarket API - dm-api

rake apps:dm-buyer-frontend:deploy[teamname,username]      # Deploy Datamarket Buyer frontend - dm-buyer-frontend
rake apps:dm-buyer-frontend:remove[teamname,username]      # Remove Datamarket Buyer frontend - dm-buyer-frontend

rake apps:dm-supplier-frontend:deploy[teamname,username]   # Deploy Datamarket Supplier frontend - dm-supplier-frontend
rake apps:dm-supplier-frontend:remove[teamname,username]   # Remove Datamarket Supplier frontend - dm-supplier-frontend

```

#### DB import for Datamark API

The task:

```
rake apps:dm-api:import_pg_dump                            # Import Datamarket API postgres DB
```

Will import a DB dump in the DB service of the app. For that, you need to pass
the parameters `dm_api_pg_dump_url="http://somehost.com/full.dump"`
and  `dm_api_pg_dump_auth_header="Auth: ..."` to download a dump.

The URL is protected by a secret header.

The import is done by running `pg_restore` inside the app containers.

### deployment tasks and pallarel deploy

The deployment can use the [multitask feature of rake](http://devblog.avdi.org/2014/04/29/rake-part-7-multitask/)
to run app deployments in parallel.

Currently is implemented in a way that each team can deploy the apps in a different thread.

This is implemented in the tasks:

```
rake team_deployment:deploy_parallel                       # Deploy in parallel all applications for all teams
rake team_deployment:remove_parallel                       # Remove in parallel all applications for all teams
```

You can change the number of workers with the option `-j #`.

These are tasks which sequencially call the specific deployment of apps per team:

```
rake team_deployment:bulkt1:deploy_all                     # Deploy all applications for team bulkt1
rake team_deployment:bulkt1:remove_all                     # Remove all applications for team bulkt1
```

They **will also capture any error** and report it at the end, to avoid interrupt
running deployments:

```
E, [2015-07-28T10:21:27.308038 #63957] ERROR -- : Some tasks failed: team_deployment:bulkt1:flask-app:deploy
```

You can call that specific task independently from command line.

Setting the option: `stop_on_error=true` will try to stop the running thread without
interrupting running deployments.


## Known Issues

### SSL errors

If you get this error `SSL_connect returned=1 errno=0 state=SSLv3 read server certificate B: certificate verify failed (OpenSSL::SSL::SSLError)` you probably have some issue with your openssl certificates in your system.

The easiest workaround is use the certificate from python before running the programs (remember install the dependencies):

```
export SSL_CERT_FILE=`python -m certifi`
```

### DataMarket Api cannot be deploy after importing DB

The deployment will try to run a DB migration and will fail. Pending investigation.

### Issues binding the postgres service instance

Postgresapi has [some](https://github.com/tsuru/postgres-api/issues/1)
[bugs](https://github.com/tsuru/postgres-api/issues/13) which might appear while deploying the app.

Some cases:

```
ERROR -- : uncaught throw #<StandardError: {"Message":"","Error":"Failed to bind the instance \"bulkt2-dm-api-db\" to the app \"dm-api-bulkt2\": role \"bulkt2_dm_c4e9c4\" already exists\n"}
```

Workaround: Try to remove the service with: `tsuru service-remove bulkt2-dm-api-db` and rerun the deployment.
