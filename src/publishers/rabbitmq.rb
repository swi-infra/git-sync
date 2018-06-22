require 'bunny'
require 'colored'

class GitSync::Publisher::RabbitMQ < GitSync::Publisher::Base
  attr_reader :host, :port, :exchange, :username, :password

  def initialize(host, port, exchange, username, password)
    @host = host
    @port = port
    @exchange = exchange
    @username = username
    @password = password

    @connection = Bunny.new(:host => @host,
                            :port => @port,
                            :user => @username,
                            :pass => @password)
    @connection.start

    raise "Unable to configure RabbitMQ Publisher: #{host}:#{port}:#{exchange}" unless @host and @exchange

    # Create channel
    channel = @connection.create_channel
    @exchange_ref = channel.fanout(@exchange)
  end

  def publish(event)
    STDERR.puts "[PublisherRabbitMQ #{host}:#{port}:#{exchange}] Publishing event #{event["type"]}".green
    @exchange_ref.publish(JSON.dump(event))
  end

end

