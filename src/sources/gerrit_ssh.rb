require 'net/ssh'
require 'colored'

class GitSync::Source::GerritSsh < GitSync::Source::Gerrit

  def initialize(gerrit_host, gerrit_port, username,
                 from, to,
                 one_shot=false,
                 publishers=[])
    super(gerrit_host, gerrit_port, username, from, to, one_shot, publishers)
  end

  def stream_events
    puts "[GerritSsh #{host}:#{port}] Streaming events through SSH (username: #{username})".blue

    Net::SSH.start(@host,
                   @username,
                   keepalive: true,
                   keepalive_interval: 15,
                   port: @port) do |ssh|

      ssh.open_channel do |channel|
        channel.exec("gerrit stream-events") do |ch, success|
          abort "could not execute command" unless success

          channel.on_data do |ch2, data|
            puts "[GerritSsh #{host}:#{port}] #{data}"
            data.each_line do |line|
              process_event(line) do |event|
                yield(event)
              end
            end
          end

          channel.on_extended_data do |ch2, type, data|
            puts "[GerritSsh #{host}:#{port}] Error #{data}".red
          end

          channel.on_eof do |ch2|
            puts "[GerritSsh #{host}:#{port}] EOF".red
          end

          channel.on_close do |ch2|
            puts "[GerritSsh #{host}:#{port}] Channel is closing!".red
          end
        end
      end

      ssh.loop
    end
  end

end

