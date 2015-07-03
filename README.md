# Tsuru Performance test suite

The Tsuru test suite is a set of jmeter-ruby-dsl scripts describing a set of performance testing scenarios.
They each can be found in the `dsl` folder and run locally or exported to jmx files for running on Blazemeter,
Flood.io or on your own servers, to provide more resources to a performance test.

Currently, these tests are only runnable against the CI environment.

## How to install

```
Brew install jmeter
git clone https://github.com/alphagov/tsuru-performance-testing
cd ./tsuru-performance-testing
bundle install
```

## How to run these tests locally

To run the tests:

```
ruby deploy_apps.rb ruby deploy_apps.rb <TSURU_TARGET_URL> 100 100
```

This will generate a jmeter.jmx file which you can load into the Jmeter gui or use in a headless mode.

However, due to https://github.com/flood-io/ruby-jmeter/issues/43 you'll need to add the following parameters to
the os_process_sampler:

 * push
 * git@ci-gandalf.tsuru2.paas.alphagov.co.uk:davas-${app_id}.git
 * master

And the following environment variables:

 * 'HOME' : '/tmp/tsuru_tmp'
 * 'GIT_SSH' : '/tmp/tsuru_tmp/ssh-wrapper'

This will deploy a thousand apps, making use of a 100 users (threads) to each deploy a 100 apps.

To clean up afterwards run:

```
ruby cleanup_apps.rb <TSURU_TARGET_URL> 100 100
```



