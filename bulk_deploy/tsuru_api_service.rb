require_relative './../dsl/ssh_helper'

class TsuruAPIService

  def initialize(logger:, api_client:, tsuru_home:)
    @logger = logger
    @api_client = api_client
    @tsuru_home = tsuru_home
  end

  def api_client
    return @api_client
  end

  def logger
    return @logger
  end

  def create_teams_and_users(team_count:, users_per_team:)
    team_users = {}

    # Login as administrator first
    self.logger.info('Login as administrator')
    self.api_client.login('administrator@gds.tsuru.gov', 'admin123')

    # Create teams and users
    i = 0
    team_count.times do
      self.logger.info("Create team #{i} [#{team_count} teams in total]")
      team = "testteam" + Time.now.to_i.to_s.reverse

      create_team(team)

      team_users[team] = []

      users_per_team.times do
        self.logger.info("Create user #{i}, [#{users_per_team} users per team]")
        email = "testuser#{i}@#{team}.co.uk"
        password = "password"

        create_user(email, password, team)

        user = {
          email: email,
          password: password,
          team: team
        }
        team_users[team].push(user)

        i += 1
      end
    end

    # Add keys to users
    team_users.each do |team,users|
      for user in users
        add_key_to_user(user)
      end
    end

    return team_users
  end

  def create_team(team)
    # Create a team
    unless self.api_client.list_teams().include? team
      self.api_client.create_team(team)
    end

    # Add the default pool to the team
    if not self.api_client.team_has_pool(team)
      self.api_client.add_team_to_pool(team)
    end
  end

  def create_user(email, password, team)
    # Create a user
    if not self.api_client.user_exists(email)
      self.api_client.create_user(email, password)
    end

    # Add the user to team
    if not self.api_client.user_in_team(email, team)
      self.api_client.add_user_to_team(team, email)
    end
  end

  def add_key_to_user(user)
    self.logger.info("Add public key for user #{user[:email]}")
    ssh_id_rsa_path = File.join(@tsuru_home, '.ssh', "id_rsa_#{user[:email]}")
    ssh_id_rsa_pub_path = File.join(@tsuru_home, '.ssh', "id_rsa_#{user[:email]}.pub")
    ssh_config_file = File.join(@tsuru_home, '.ssh', 'config')
    ssh_wrapper_path = File.join(@tsuru_home, 'ssh-wrapper')

    # Generate a new ssh key
    SshHelper.generate_key(ssh_id_rsa_path)
    SshHelper.write_config(
      ssh_config_file,
      'UserKnownHostsFile' => '/dev/null',
      'StrictHostKeyChecking' => 'no',
      'IdentityFile' => ssh_id_rsa_path
    )
    SshHelper.write_ssh_wrapper(ssh_wrapper_path, ssh_config_file)

    # Load public key from the file
    temp_file = File.read(ssh_id_rsa_pub_path)
    public_key = temp_file.gsub(/\n/, '')
      .gsub(/-----BEGIN PUBLIC KEY-----/, '')
      .gsub(/-----END PUBLIC KEY-----/, '')

    self.api_client.login(user[:email], user[:password])
    self.api_client.add_key(public_key)

    user[:key] = ssh_id_rsa_path
  end

end
