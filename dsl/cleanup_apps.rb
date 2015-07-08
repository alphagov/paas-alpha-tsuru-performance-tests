require "rubygems"
require "ruby-jmeter"
require "cgi"

if ARGV.size != 4
  puts "------- Tsuru perf test: ERROR! --------"
  puts "      Usage:"
  puts "      Please specify a tsuru target env, tsuru root hostname"
  puts "      a thread count and a loop count for each thread.\n"
  puts "      Example:"
  puts "          bundle exec ruby cleanup_apps.rb ci tsuru2.paas.alphagov.co.uk 1 1"
  exit 1
end

environment  = ARGV[0]
host_suffix  = ARGV[1]
thread_count = ARGV[2].to_i
loop_count   = ARGV[3].to_i


test do
  counter "CounterConfig.name"                  => "app_id",
          "CounterConfig.start"                 => 1,
          "CounterConfig.incr"                  => 1,
          "CounterConfig.per_user"              => "false",
          "CounterConfig.reset_on_tg_iteration" => "false"

  defaults domain: environment + '-api.' + host_suffix, protocol: 'https'

  header [
    { name: "Content-Type", value: "application/json" }
  ]
  auth_url = "/users/" + CGI.escape("administrator@gds.tsuru.gov") + "/tokens"
  threads count: thread_count, loops: loop_count do
    Once do
      post url: auth_url, raw_body: '{ "password": "admin123" }' do
        extract regex: '"token":"(\w+)",', name: "auth_token"
      end
    end

    # We have our auth token - we now set a bearer authentication.
    header [
      { name: "Authorization", value: "bearer ${auth_token}" }
    ]
    delete url: "/apps/testapp-${app_id}"
  end

  debug_sampler
  view_results_tree
end.jmx
