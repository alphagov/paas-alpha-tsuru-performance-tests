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
cd  ./dsl
bundle exec ruby deploy_apps.rb <TSURU_ENVIRONMENT_NAME>  <TSURU_TARGET_HOST> 100 100
```

This will generate a jmeter.jmx file which you can load into the Jmeter gui or use in a headless mode.

However, due to https://github.com/flood-io/ruby-jmeter/issues/43 you'll need to add the following parameters to
the os_process_sampler:

 * push
 * git@ci-gandalf.tsuru2.paas.alphagov.co.uk:testapp-${app_id}.git
 * master

And the following environment variables:

 * 'HOME' : '/tmp/tsuru_tmp'
 * 'GIT_SSH' : '/tmp/tsuru_tmp/ssh-wrapper'

This will deploy a thousand apps, making use of a 100 users (threads) to each deploy a 100 apps.

To clean up afterwards run:

```
cd  ./dsl
bundle exec ruby cleanup_apps.rb <TSURU_ENVIRONMENT_NAME> <TSURU_TARGET_HOST> 100 100
```



### Example OS Process Sampler

Once you've generated the xml for deploying the applications, your systemsampler section will need to look similar to this:

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

