require 'yaml'
require 'ap'

class GitSync::Config
  attr_reader :config
  attr_reader :sources

  def initialize
    @config = nil
  end

  def load_from_file(path)
    file = File.open(path)
    load file.read
  end

  def load(yaml)
    @config = YAML.load(yaml)

    default_to = nil
    if @config["global"]
      default_to = @config["global"]["to"]
      global_one_shot = @config["global"]["oneshot"]
    end
    global_one_shot ||= false

    if not @config["sources"]
      raise "No 'sources' section specified in the config file."
    end

    @sources = []
    @config["sources"].each do |cfg|
      type = cfg["type"] || "single"

      source = case type
      when "single"
        from = cfg["from"]
        name = File.basename(cfg["from"], ".*") + ".git"
        to = cfg["to"] || File.join(default_to, name)
        GitSync::Source::Single.new(from, to)

      when "gerrit"
        host = cfg["host"]
        port = cfg["port"] || 29418
        username = cfg["username"]
        from = cfg["from"]
        to = cfg["to"] || default_to
        one_shot = cfg["oneshot"] || global_one_shot
        source = GitSync::Source::GerritSsh.new(host, port, username, from, to, one_shot)

        if cfg["filters"]
          cfg["filters"].each do |filter|
            if filter.start_with? "/" and filter.end_with? "/"
              filter = Regexp.new( filter.gsub(/(^\/|\/$)/,'') )
            end

            source.filters.push filter
          end
        end

        source

      when "gerrit-rabbitmq"
        gerrit_host = cfg["gerrit_host"]
        gerrit_port = cfg["gerrit_port"] || 29418
        username = cfg["username"]
        rabbitmq_host = cfg["rabbitmq_host"] || gerrit_host
        rabbitmq_port = cfg["rabbitmq_port"] || 5672
        exchange = cfg["exchange"]
        rabbitmq_username = cfg["rabbitmq_username"]
        rabbitmq_password = cfg["rabbitmq_password"]
        from = cfg["from"]
        to = cfg["to"] || default_to
        one_shot = cfg["oneshot"] || global_one_shot
        source = GitSync::Source::GerritRabbitMQ.new(gerrit_host, gerrit_port,
                                                     username,
                                                     rabbitmq_host, rabbitmq_port,
                                                     exchange,
                                                     rabbitmq_username, rabbitmq_password,
                                                     from, to, one_shot)

        if cfg["filters"]
          cfg["filters"].each do |filter|
            if filter.start_with? "/" and filter.end_with? "/"
              filter = Regexp.new( filter.gsub(/(^\/|\/$)/,'') )
            end

            source.filters.push filter
          end
        end

        source

      else
        raise "Unknown source type '#{type}'"
      end

      @sources.push source
    end
  end
end

