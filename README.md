# Tsuru Performance test suite

The Tsuru test suite is a set of jmeter-ruby-dsl scripts describing a set of performance testing scenarios.
They each can be found in the `dsl` folder and run locally or exported to jmx files for running on Blazemeter,
Flood.io or on your own servers, to provide more resources to a performance test.

Currently, these tests are only runnable against the CI environment.

## How to install

 * mac osx:
	`brew install jmeter`
 * Ubuntu / Debian:
	`apt-get install jmeter`
 * Other:
 	`http://jmeter.apache.org/usermanual/get-started.html`

```
git clone https://github.com/alphagov/tsuru-performance-testing
cd ./tsuru-performance-testing
bundle install
```

For running the jmeter DSL scripts, we use ruby 2.2.2. It is recommended that you make use of [rvm](https://rvm.io/) or [rbenv](http://rbenv.org/).


## How to run these tests locally

### To run the deploy_apps test script:

```
cd  ./dsl
bundle exec ruby deploy_apps.rb <TSURU_ENVIRONMENT_NAME> <TSURU_TARGET_HOST> 100 100
```

This will generate a jmeter.jmx file which you can load into the Jmeter gui or use in a headless mode.

However, [due a bug in ruby-jmeter](https://github.com/flood-io/ruby-jmeter/issues/43), we need to add addional configuration.
See below for details, but this can be automatically added by running:

```
./add_systemsampler.sh  <TSURU_ENVIRONMENT_NAME> <TSURU_TARGET_HOST>
```

This will deploy a 100x100, that is 10k apps, making use of a 100 users (threads) to each deploy a 100 apps.

Once you have opened the file in jmeter GUI and added the correct parameters or ammended the file,
you can run the jmx file in a headless manner:

```
jmeter -n -t jmeter.jmx -l my_results.jtl
```

This will output the results of the run to the `my_results.jtl` file for further analysis.

To clean up afterwards, generate a new jmx file with cleanup instructions:

```
bundle exec ruby cleanup_apps.rb <TSURU_ENVIRONMENT_NAME> <TSURU_TARGET_HOST> 100 100
jmeter -n -t jmeter.jmx -l my_results.jtl
```

and run it:

```
jmeter -n -t jmeter.jmx -l my_results.jtl
```

### To run the traffic load test for deployed apps tests

Before you begin your test run, make sure that you have run the `generate_traffic_data.rb` script.
This will create three csv files in the DSL folder; one for the flask example app, one for the
java jetty app, one for digital marketplace and one for GOV.UK frontend application.

Each one of these csv files contains a list of app urls for a deployed instance of that application
as exposed by the Tsuru platform. They are then consumed by the `create_traffic_for_deployed_apps.rb`
jmeter dsl file.

To create the jmeter jmx file for this performance test, run:

```
bundle exec ruby create_traffic_for_deployed_apps.rb <TSURU_ENVIRONMENT_NAME> <TSURU_TARGET_HOST> 100 100

```

Where '100 100' cli args will create a 100 threads that will execute 100 times. The script will create
a jmeter.jmx file in the local directory that can then be run via jmeter headless mode thus:

```
jmeter -n -t jmeter.jmx -l my_results.jtl
```

It has been helpful to have the graphana dashboards preconfigured to running this performance test, so
that the current state and affect of the performance test can be viewed.

## Known issues

### Example OS Process Sampler

There is [a bug in ruby-jmeter](https://github.com/flood-io/ruby-jmeter/issues/43)
that requires you to add the following parameters to
the `os_process_sampler`:

 * push
 * git@ci-gandalf.tsuru2.paas.alphagov.co.uk:testapp-${app_id}.git
 * master

And the following environment variables:

 * 'HOME' : '/tmp/tsuru_tmp'
 * 'GIT_SSH' : '/tmp/tsuru_tmp/ssh-wrapper'

We need to amend the file once you've generated the xml for deploying the
applications, your systemsampler section will need to look similar to this:

```
 <SystemSampler guiclass="SystemSamplerGui" testclass="SystemSampler" testname="OsProcessSampler" enabled="true">
          <boolProp name="SystemSampler.checkReturnCode">false</boolProp>
          <stringProp name="SystemSampler.expectedReturnCode">0</stringProp>
          <stringProp name="SystemSampler.command">/usr/bin/git</stringProp>
          <elementProp name="SystemSampler.arguments" elementType="Arguments" guiclass="ArgumentsPanel" testclass="Arguments" testname="OsProcessSampler" enabled="true">
            <collectionProp name="Arguments.arguments">
              <elementProp name="" elementType="Argument">
                <stringProp name="Argument.name"></stringProp>
                <stringProp name="Argument.value">push</stringProp>
                <stringProp name="Argument.metadata">=</stringProp>
              </elementProp>
              <elementProp name="" elementType="Argument">
                <stringProp name="Argument.name"></stringProp>
                <stringProp name="Argument.value">git@ci-gandalf.tsuru2.paas.alphagov.co.uk:testapp-${app_id}.git</stringProp>
                <stringProp name="Argument.metadata">=</stringProp>
              </elementProp>
              <elementProp name="" elementType="Argument">
                <stringProp name="Argument.name"></stringProp>
                <stringProp name="Argument.value">master</stringProp>
                <stringProp name="Argument.metadata">=</stringProp>
              </elementProp>
            </collectionProp>
          </elementProp>
          <elementProp name="SystemSampler.environment" elementType="Arguments" guiclass="ArgumentsPanel" testclass="Arguments" testname="OsProcessSampler" enabled="true">
            <collectionProp name="Arguments.arguments">
              <elementProp name="HOME" elementType="Argument">
                <stringProp name="Argument.name">HOME</stringProp>
                <stringProp name="Argument.value">/tmp/tsuru_tmp</stringProp>
                <stringProp name="Argument.metadata">=</stringProp>
              </elementProp>
              <elementProp name="GIT_SSH" elementType="Argument">
                <stringProp name="Argument.name">GIT_SSH</stringProp>
                <stringProp name="Argument.value">/tmp/tsuru_tmp/ssh-wrapper</stringProp>
                <stringProp name="Argument.metadata">=</stringProp>
              </elementProp>
            </collectionProp>
          </elementProp>
          <stringProp name="SystemSampler.directory">/tmp/tsuru_tmp/example-java-jetty</stringProp>
        </SystemSampler>
```

We provide a script `add_systemsampler.sh` to do this automatically

