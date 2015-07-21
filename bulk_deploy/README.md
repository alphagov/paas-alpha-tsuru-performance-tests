Deploying Many Teams And Many Apps
==================================

This directory contains a script to deploy potentially a large amount of teams and applications.

The script has multiple options such as number of teams or number of units per app.

You can deploy example usage and all options and their default values by running the script without any arguments:

```
bundle exec ruby deploy.rb -e richard -h tsuru2.paas.alphagov.co.uk
Usage: bundle exec deploy.rb action [options]
Example: bundle exec deploy.rb --environment perf-env --host-suffix tsuru2.paas.alphagov.co.uk apply
    -e, --environment=e              Environment [Required]
    -h, --host-suffix=h              Host suffix [Required]
    -at, --api-token=at              API Token [Required]
    -st, --search-api-token=st       Search API Token [Required]
    -t, --team-count=t               Team count [Default: 2]
    -u, --users-per-team=u           Users per team [Default: 7]
    -a, --apps-per-team=a            Applications per team [Default: 5]
    -l, --log-level=l                Log level [Default: info]
    -n, --units_per_app=n            Units per application [Default: 3]
    -s, --state-file=f               State file [Default: /Users/richardknop/github.com/alphagov/tsuru-performance-tests/bulk_deploy/deploy.state]
```

There are two actions:

- apply: deploys teams and apps
- destroy: removes deployed teams and apps (based on the state file)

By default, these 5 apps are deployed right now:

- example Java Jetty app
- example Flask app
- Digital Marketplace admin frontend app
- Digital Marketplace admin suppliers app
- Digital Marketplace admin buyers app

Digital Marketplace backend apps are not deployed yet, so frontend apps use preview environment.

In the future we want to improve this script to deploy our own DM backend apps without relying on the preview environment.

Sample Usage
------------

```
bundle exec ruby deploy.rb -e richard -h tsuru2.paas.alphagov.co.uk apply -t 2 -n 3 -T ourtoken -S oursearchtoken
```

Will create 2 teams, each with 7 users and deploy 5 apps (listed above) for the each team with 3 units per app.

It will use `richard` environment on GCE.
