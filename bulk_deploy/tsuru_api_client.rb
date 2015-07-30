require "net/http"
require "uri"
require "cgi"
require "json"
require "yajl"
require "openssl"

class TsuruAPIClient

  # Default headers added to each request
  HEADERS = {
    "Content-Type"    => "application/json",
    "Accept-Encoding" => "gzip",
  }

  VERB_MAP = {
    :get    => Net::HTTP::Get,
    :post   => Net::HTTP::Post,
    :put    => Net::HTTP::Put,
    :delete => Net::HTTP::Delete
  }

  def initialize(logger:, environment:, host:, protocol: "https://")
    # Parse the Tsuru API domain and create a HTTP client
    @protocol = protocol
    @uri = URI.parse(protocol + environment + "-api." + host)
    @logger = logger
  end

  def login(email, password)
    email = URI.escape(email)
    path = "/users/#{email}/tokens"
    response = request_json(
      method: :post,
      path: path,
      params: {
        :password => password,
      }
    )
    @token = response["token"]
    @is_admin = response["is_admin"]
    return @token
  end

  def create_user(email, password)
    request_json(
      method: :post,
      path: "/users",
      params: {
        :email => email,
        :password => password,
      }
    )
  end

  def user_exists(email)
    response = request_json(
      method: :get,
      path: "/users"
    )

    response.each do |d|
      if d["Email"] == email
        return true
      end
    end

    return false
  end

  def user_in_team(email, team)
    response = request_json(
      method: :get,
      path: "/users"
    )

    response.each do |d|
      if d["Email"] == email and d["Teams"].include? team
        return true
      end
    end

    return false
  end

  def add_key(pubkey)
    request_json(
      method: :post,
      path: "/users/keys",
      params: {
        :key => pubkey,
        :name => "rsa",
      }
    )
  end

  def create_team(team)
    response = request_json(
      method: :post,
      path: "/teams",
      params: {
        :name => team,
      }
    )
  end

  def list_teams()
    response = request_json(
      method: :get,
      path: "/teams"
    )

    teams = Array.new()
    response.each do |team|
      teams.push(team["name"])
    end

    return teams
  end

  def remove_team(team)
    request(
      method: :delete,
      path: "/teams/#{team}"
    )
  end

  def remove_user(email)
    email = URI.escape(email)
    request(
      method: :delete,
      path: "/users?user=#{email}"
    )
  end

  def team_has_pool(team, pool="default")
    response = request_json(
      method: :get,
      path: "/pools"
    )

    response.each do |d|
      if d["Team"] == team and d["Pools"].include? pool
        return true
      end
    end

    return false
  end

  def add_team_to_pool(team, pool="default")
    request_json(
      method: :post,
      path: "/pool/team",
      params: {
        :pool => pool,
        :teams => [team],
      }
    )
  end

  def remove_team_from_pool(team, pool="default")
    request(
      method: :delete,
      path: "/pool/team",
      params: {
        :pool => pool,
        :teams => [team],
      }
    )
  end

  def create_app(name, platform, team_owner=nil, pool=nil)
    request_json(
      method: :post,
      path: "/apps",
      params: {
        :platform => platform,
        :name      => name,
        :teamowner => team_owner,
        :pool      => pool,
      }
    )
  end

  def get_app_info(app_name)
    request_json(
      method: :get,
      path: "/apps/#{app_name}"
    )
  end

  def get_app_url(app_name)
    get_app_info(app_name)["ip"]
  end

  def add_units(units, app_name)
    objects = request_json(
      method: :put,
      path: "/apps/#{app_name}/units",
      body: units.to_s
    )

    for obj in objects
      @logger.debug(obj["Message"])
    end
  end

  def remove_units(units, app_name)
    request(
      method: :delete,
      path: "/apps/#{app_name}/units",
      body: units.to_s
    )
  end

  def list_apps()
    response = request_json(
      method: :get,
      path: "/apps"
    )

    apps = Array.new()
    response.each do |app|
      apps.push(app["name"])
    end

    return apps
  end

  def app_has_service(app_name, instance_name)
    response = request_json(
      method: :get,
      path: "/services/instances/#{instance_name}"
    )
    return response["Apps"].include? app_name
  end

  def get_app_repository(app_name)
    request_json(
      method: :get,
      path: "/apps/#{app_name}"
    )["repository"]
  end

  def set_env_var(app_name, key, value)
    request_json(
      method: :post,
      path: "/apps/#{app_name}/env",
      params: {
        "#{key}": value
      }
    )
  end

  def get_env_vars(app_name)
    hash = {}

    env_vars = request_json(
      method: :get,
      path: "/apps/#{app_name}/env",
    )

    for env_var_arr in env_vars
      hash[env_var_arr["name"]] = env_var_arr["value"]
    end

    return hash
  end

  def unset_env_var(app_name, key, value)
    request(
      method: :delete,
      path: "/apps/#{app_name}/env",
      params: {
        key: value
      }
    )
  end

  def remove_app(name)
    request(
      method: :delete,
      path: "/apps/#{name}"
    )
  end

  def add_user_to_team(team, email)
    email = URI.escape(email)
    request_json(
      method: :put,
      path: "/teams/#{team}/#{email}"
    )
  end

  def remove_user_from_team(team, email)
    email = URI.escape(email)
    request(
      method: :delete,
      path: "/teams/#{team}/#{email}"
    )
  end

  def add_service_instance(service_name, name)
    request_json(
      method: :post,
      path: "/services/instances",
      params: {
        :service_name => service_name,
        :name => name,
      }
    )
  end

  def list_service_instances()
    response = request_json(
      method: :get,
      path: "/services/instances"
    )

    instances = Array.new()
    response.each do |d|
      instances = instances | d["instances"]
    end

    return instances
  end

  def remove_service_instance(name)
    name = URI.escape(name)
    request(
      method: :delete,
      path: "/services/instances/#{name}"
    )
  end

  def bind_service_to_app(name, app_name)
    objects = request_json(
      method: :put,
      path: "/services/instances/#{name}/#{app_name}"
    )

    for obj in objects
      @logger.debug(obj["Message"])
    end
  end

  def unbind_service_from_app(name, app_name)
    request(
      method: :delete,
      path: "/services/instances/#{name}/#{app_name}"
    )
  end

  private

  def request_json(method:, path:, params: {}, body: "")
    @last_response = request(
      method: method,
      path: path,
      params: params,
      body: body
    )

    if @last_response.body.nil? or @last_response.body.empty?
      return {}
    end

    def error_handler()
      @logger.debug("The last response was:")
      @logger.debug(@last_response.body)
      throw StandardError.new(@last_response.body)
    end

    objects = []
    parser = Yajl::Parser.new
    parser.on_parse_complete = lambda{|obj| objects.push(obj)}

    begin
      json = StringIO.new(@last_response.body)
      parser.parse(json)
    rescue => err
      @logger.error(err)
      error_handler()
    end

    for obj in objects
      if obj.include? "Error"
          error_handler()
      end
    end

    if objects.length == 1
      return objects[0]
    end

    return objects
  end

  def http
    http = Net::HTTP.new(@uri.host, @uri.port)

    # Set SSL flag to true if protocol is HTTPS
    if @protocol == "https://"
      http.use_ssl = true
    end

    http
  end

  def request(method:, path:, params: {}, body: "")
    case method
    when :get
      full_path = encode_path_params(path, params)
      request = VERB_MAP[method.to_sym].new(full_path)
    else
      request = VERB_MAP[method.to_sym].new(path)
      if body != ""
        request.body = body
      else
        request.body = JSON.dump(params)
      end
    end

    HEADERS.each do |k,v|
      request[k] = v
    end

    if @token != nil
      request["Authorization"] = "Bearer #{@token}"
    end

    response = http.request(request)

    # If request failed, raise exception
    if response.code >= "400"
      @logger.error("Request: #{request.method} #{request.path} #{request.body}")
      @logger.error("Response Body: #{response.body}")
      throw response
    end

    return response
  end

  def encode_path_params(path, params)
    encoded = URI.encode_www_form(params)
    [path, encoded].join("?")
  end

end
