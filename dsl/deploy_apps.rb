require 'rubygems'
require 'ruby-jmeter'
require 'cgi'
require 'net/ssh'
require './ssh_helper'
require 'fileutils'

if ARGV.size != 4
  puts '------- Tsuru perf test: ERROR! --------'
  puts '      Usage:'
  puts '      Please specify a tsuru target environment,'
  puts '      a tsuru host suffix, a thread count '
  puts '      and a loop count for each thread.'
  puts '      Example:'
  puts '           bundle exec ruby deploy_apps.rb ci tsuru2.paas.alphagov.co.uk 1 1    '
  exit 1
end

environment  = ARGV[0]
host_suffix  = ARGV[1]
thread_count = ARGV[2].to_i
loop_count   = ARGV[3].to_i

tsuru_home = '/tmp/tsuru_tmp'
FileUtils.rm_rf(tsuru_home)
Dir.mkdir(tsuru_home) unless File.exist? tsuru_home
ssh_id_rsa_path = File.join(tsuru_home, '.ssh', 'id_rsa')
ssh_id_rsa_pub_path = File.join(tsuru_home, '.ssh', 'id_rsa.pub')
ssh_config_file = File.join(tsuru_home, '.ssh', 'config')
ssh_wrapper_path = File.join(tsuru_home, 'ssh-wrapper')

output = `cd #{tsuru_home} && git clone https://github.com/alphagov/example-java-jetty`

SshHelper.generate_key(ssh_id_rsa_path)
SshHelper.write_config(
  ssh_config_file,
  'StrictHostKeyChecking' => 'no',
  'IdentityFile' => ssh_id_rsa_path
)
SshHelper.write_ssh_wrapper(ssh_wrapper_path, ssh_config_file)

temp_file = File.read(ssh_id_rsa_pub_path)
public_key = temp_file.gsub(/\n/, '').gsub(/-----BEGIN PUBLIC KEY-----/, '').gsub(/-----END PUBLIC KEY-----/, '')

test do
  counter 'CounterConfig.name' => 'app_id',
          'CounterConfig.start' => 1,
          'CounterConfig.incr' => 1,
          'CounterConfig.per_user' => 'false',
          'CounterConfig.reset_on_tg_iteration' => 'false'

  defaults domain: environment + '-api.' + host_suffix, protocol: 'https'

  header [
    { name: 'Content-Type', value: 'application/json',
      name: 'Accept-Encoding', value: 'gzip' }
  ]

  threads count: thread_count, loops: loop_count do
    Once do
      auth_url = '/users/' + CGI.escape('administrator@gds.tsuru.gov') + '/tokens'
      post url: auth_url,
           raw_body: '{ "password": "admin123" }' do
             extract regex: '"token":"(\w+)",',
                    name: 'auth_token'
      end
    end

    # We have our auth token - we now set a bearer authentication.
    header [
      { name: 'Authorization', value: 'bearer ${auth_token}' }
    ]

    Once do
      post url: '/users/keys',
           raw_body: '{"key": "' + public_key + '", "name": "rsa" }'
    end

    post url: '/apps',
         raw_body: '{"name":"testapp-${app_id}","plan":{"name":""},"platform":"java","pool":"","teamOwner":""}'

    os_process_sampler 'SystemSampler.command'     => 'git',
                       'SystemSampler.arguments'   => %w(push origin master),
                       'SystemSampler.directory'   => '#{tsuru_home}/example-java-jetty',
                       'SystemSampler.environment' => { 'HOME' => tsuru_home, 'GIT_SSH' => ssh_wrapper_path }
  end

  debug_sampler
  view_results_tree
end.jmx