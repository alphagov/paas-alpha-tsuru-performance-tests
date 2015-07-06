require "rubygems"
require "ruby-jmeter"
require "cgi"

if ARGV.size != 3
  puts "\n\n------- Tsuru perf test: ERROR! --------"
  puts "      Usage:"
  puts "      Please specify a tsuru target domain,  "
  puts "  a thread count and a loop count for each thread.\n"
  puts "      Example:"
  puts "          \n\n"
  exit 1
end

test do
  counter "CounterConfig.name" => "app_id",
          "CounterConfig.start" => 1,
          "CounterConfig.incr" => 1,
          "CounterConfig.per_user" => "false",
          "CounterConfig.reset_on_tg_iteration" => "false"

  defaults domain: ARGV[0], protocol: "https"

  header [
    { name: "Content-Type", value: "application/json" }
  ]
  auth_url = "/users/" + CGI.escape("administrator@gds.tsuru.gov") + "/tokens"
  threads count: ARGV[1].to_i, loops: ARGV[2].to_i do
    Once do
      post url: auth_url,
        raw_body: '{ "password": "admin123" }' do
        extract regex: '"token":"(\w+)",', name: "auth_token"
      end
    end

    # We have our auth token - we now set a bearer authentication.
    header [
      { name: "Authorization", value: "bearer ${auth_token}" }
    ]
    delete url: "/apps/davas-${app_id}"
  end

  debug_sampler
  view_results_tree
end.run
