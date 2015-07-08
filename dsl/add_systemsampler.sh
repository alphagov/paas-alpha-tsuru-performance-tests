#!/bin/sh

DEPLOY_ENV=$1
TSURU_TARGET_HOST=$2

if [ -z "$DEPLOY_ENV" -o -z "$TSURU_TARGET_HOST" ]; then
	echo "Usage: $0 <environment_id>"
fi


cat <<EOF > /tmp/system_sampler.txt
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
                <stringProp name="Argument.value">git@${DEPLOY_ENV}-${TSURU_TARGET_HOST}:testapp-\${app_id}.git</stringProp>
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
EOF

cp jmeter.jmx jmeter.jmx.orig
awk '/\<SystemSampler/ { system("cat /tmp/system_sampler.txt") }  /<SystemSampler/,/<\/SystemSampler>/ { next; }  // { print } ' < jmeter.jmx.orig > jmeter.jmx

