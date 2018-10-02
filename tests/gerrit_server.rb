
require 'docker'
require 'net/http'
require 'timeout'

class GerritServer
  attr_reader :name
  attr_reader :container

  def initialize(name)
    @name = name
    @start_count = 0
    @auth_cookie = nil
    @x_gerrit_auth = nil

    if ENV['GERRIT_CONTAINER_ID']
      @container = Docker::Container.get(ENV['GERRIT_CONTAINER_ID'])
      @start_count = detect_initial_start_count
    else
      init_new_server
    end

    puts @start_count

    wait_server_init
  end

  def detect_initial_start_count
    start_detected = 0

    args = ["docker", "logs", id]

    begin
      IO.popen(args, :err=>[:child, :out]) do |io|
        io.readlines.each do |line|
          #puts "#{name}: gerrit: #{line}"

          if line[/Gerrit Code Review .* ready/]
            start_detected += 1
            puts "#{start_detected}".red
          end
        end

        io.close
      end
    rescue EOFError
    end

    start_detected
  end

  def detect_start_count(expected=1)
    start_detected = 0

    args = ["docker", "logs", "-f", id]

    puts "Wait #{expected}"

    begin
      IO.popen(args, :err=>[:child, :out]) do |io|
        reached = false

        io.each_line do |line|
          #puts "#{name}: gerrit: #{line}"

          if line[/Gerrit Code Review .* ready/]
            start_detected += 1
            STDERR.puts "#{start_detected}".blue
            if start_detected >= expected
              Process.kill("TERM", io.pid)
              STDERR.puts "Reached #{expected}".blue
              reached = true
              break
            end
          end
        end

        io.close
      end
    rescue EOFError
      puts "EOF".red
    end

    start_detected
  end

  def wait_server_init
    puts "#{name}: gerrit: waiting for server init"

    waiting_thread = Thread.new do
      while true
        sleep 10
        puts "#{name}: gerrit: still waiting ..."
      end
    end

    if true
      detect_start_count(@start_count)
    else
      ap desc
      container.streaming_logs(stdout: true, stderr: true) do |stream, chunk|
        puts "#{name}: gerrit: #{chunk}"
        if chunk[/Gerrit Code Review .* ready/]
          break
        end
      end
    end

    waiting_thread.kill
    puts "#{name}: gerrit: server init done"
  end

  def init_new_server
    image_name = 'quay.io/swi-infra/gerrit:latest'

    puts "#{name}: gerrit: pulling image #{image_name}"
    Docker::Image.create('fromImage' => image_name)
    puts "#{name}: gerrit: pulling image (done)"

    puts "#{name}: gerrit: creating container"
    @container ||= Docker::Container.create('Image' => image_name,
                                            'Env' => [ 'AUTH_TYPE=DEVELOPMENT_BECOME_ANY_ACCOUNT' ],
                                            )

    raise "Unable to create Gerrit container" if not container

    puts "#{name}: container #{id} created"

    container.start

    puts "#{name}: container #{id} started"

    @start_count += 1
  end

  def id
    container.id[0..10]
  end

  def teardown
    return if not container

    if ENV['GERRIT_SKIP_TEARDOWN']
      puts "Skipping teardown"

      if not ENV['GERRIT_CONTAINER_ID']
        puts "To re-use this container:"
        puts "\texport GERRIT_CONTAINER_ID=#{id}"
      end

      return
    end

    container.kill!
    puts "#{name}: container #{id} killed"

    container.remove
    puts "#{name}: container #{id} removed"
  end

  def restart
    container.kill!
    puts "#{name}: container #{id} killed"

    container.start
    puts "#{name}: container #{id} started"

    @start_count += 1
    @desc = nil

    wait_server_init
  end

  def desc
    @desc ||= container.json
  end

  def host
    desc["NetworkSettings"]["IPAddress"]
  end

  def http_port
    8080
  end

  def ssh_port
    29418
  end

  def username
    "admin"
  end

  def login(account_id=1000000)

    # Get GerritAccount cookie
    path = "/login/%23%2F?account_id=#{account_id}"
    req_headers = {}
    req = Net::HTTP::Get.new(path)
    response = Net::HTTP.new(host, http_port).start {|http| http.request(req) }
    if response.code != "302"
      raise "Unable to login"
    end

    @auth_cookie = response.header['set-cookie'][/^(.*);/,1]

    # Get XSRF_TOKEN cookie
    path = "/"
    req_headers["Cookie"] = auth_cookie

    req = Net::HTTP::Get.new(path, initheader=req_headers)
    response = Net::HTTP.new(host, http_port).start {|http| http.request(req) }
    if response.code != "200"
      raise "Unable to login"
    end

    @x_gerrit_auth = response.header['set-cookie'][/^(.*);/,1]
  end

  def auth_cookie
    login if not @auth_cookie
    @auth_cookie
  end

  def x_gerrit_auth
    login if not @x_gerrit_auth
    @x_gerrit_auth[/XSRF_TOKEN=(.*)/, 1]
  end

  def base_headers
    {
      'X-Gerrit-Auth' => x_gerrit_auth,
      'Cookie' => auth_cookie
    }
  end

  def add_ssh_key(ssh_key)
    path = "/accounts/self/sshkeys"
    req = Net::HTTP::Post.new(path, initheader=base_headers)
    req.body = ssh_key
    response = Net::HTTP.new(host, http_port).start {|http| http.request(req) }
    if response.code != "201"
      puts response.code
      puts response.body
      raise "Unable to add the ssh key"
    end
  end

  def create_project(project_name)
    description ||= "Description for '#{project_name}'"

    path = "/projects/#{project_name}"
    message = {
      "name" => project_name
    }

    req_headers = base_headers
    req_headers['Content-Type'] = 'application/json'

    req = Net::HTTP::Put.new(path, initheader=req_headers)
    req.body = message.to_json
    response = Net::HTTP.new(host, http_port).start { |http| http.request(req) }

    if response.code != "201"
      puts response.code
      puts response.body
      raise "Unable to create project #{project_name}"
    end

    JSON.parse(response.body.gsub(")]}'",""))
  end
end
