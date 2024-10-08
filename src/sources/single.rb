require 'colored'
require 'git'
require 'date'
require 'fileutils'
require 'timeout'

class GitSync::Source::Single < GitSync::Source::Base
  attr_reader :from, :to, :publishers

  EXIT_CORRUPTED = 3

  def initialize(from, to, publishers=[], opts={})
    super(publishers)

    @dry_run = opts[:dry_run] || false
    @from = from
    @to = to
    @done = false
    @mutex = Mutex.new
    @queue = nil
    @event_queue = Queue.new

    # If it's a local repository
    if @from.start_with? "/"
      if File.exist? @from
        return
      elsif File.exist? "#{@from}.git" # Bare
        @from = "#{@from}.git"
      else
        throw "Unable to sync '#{@from}"
      end
    end
  end

  def to_s
    "<Source::Single '#{from}' -> '#{to}'>"
  end

  def add_event(event)
    @event_queue.push(event)
  end

  def work(queue)
    @queue = queue

    # Perform sync before forwarding messages so when the downstream client receives the messages,
    # the updated data are available.
    # If lock cannot be acquired, try again later.
    res = @mutex.try_lock
    if res
      # Empty the event_queue and place the contents in a local queue.
      event_queue_snapshot = []
      until @event_queue.empty?
        event_queue_snapshot.push @event_queue.pop
      end

      events = event_queue_snapshot.join(",")
      puts "[#{DateTime.now} #{to}] Starting sync for events [#{events}] ..."

      # Perform sync from Gerrit.
      sync_result = sync!
      @mutex.unlock

      # Publish the events requiring sync.
      until event_queue_snapshot.empty?
        event = event_queue_snapshot.pop

        if not sync_result or not event.check_updated(self)
          if event.sync_count >= 10
            puts "[#{DateTime.now} #{to}] Unable to sync #{event} after 10 tries ..."
            puts "[#{DateTime.now} #{to}] Publishing the event anyway ..."
            publish(event)
          else
            # Re-queue the event
            event.sync_count += 1
            puts "[#{DateTime.now} #{to}] Check for #{event} failed [#{event.sync_count} tries], retrying in 10s..."
            Thread.new(self, queue, event) { |s, q, e|
              begin
                sleep(10)
                s.add_event(e)
                q.push s
              rescue => ex
                STDERR.puts "Error while rescheduling event #{e}: #{ex}".red
              end
            }
          end
        else
          publish(event)
        end
      end

      puts "[#{DateTime.now} #{to}] Sync for events [#{events}] done (leftovers=#{@event_queue.length}) ..."

      # If in the meantime there has been more events queued up, that implies their work request
      # has not be fulfilled because they can't get a lock. Place ourselves back in the queue.
      if not @event_queue.empty?
        queue.push self
      end
    end
  end

  def wait
    loop do
      sleep 0.1
      return if @done
    end
  end

  def git
    @git ||= Git.bare(to)
  end

  def check_corrupted
    puts "[#{DateTime.now} #{to}] Checking for corruption".yellow
    if git.lib.fsck
      puts "[#{DateTime.now} #{to}] Repository OK".green
      return
    end

    handle_corrupted

    # Exit the current process, as to warn the parent that there is
    # a corruption going on.
    exit EXIT_CORRUPTED
  end

  def handle_corrupted
    STDERR.puts "[#{DateTime.now} #{to}] Corrupted".red
    # Remove the complete repository by default
    FileUtils.rm_rf(to)
  end

  # Check that revision is present in the ref
  def check_ref(ref, revision)
    # First check that revision is present
    begin
      git.show(revision)
    rescue Git::GitExecuteError => e
      STDERR.puts "[#{DateTime.now} #{to}] Issue when checking revision #{revision}: #{e}".yellow
      return false
    end

    # TODO: check that branch and tags contains the change
    return true
  end

  def update_symref(from, to)
    begin
      # Query the symbolic ref from remote if any
      remote_refs = git.ls_remote(["--symref", "#{from}"])

      remote_refs.each do |line|
        sym_ref = (/^ref: +(?<sha>[^ ]+)\t(?<name>[^ ]+)/i).match(line)

        if sym_ref
          from_symref_sha = sym_ref[:sha]
          from_symref_name = sym_ref[:name]

          if not from_symref_name.nil? and not from_symref_sha.nil?
            # Get current symbolic ref from local
            begin
              to_symref_sha = git.symbolic_ref(["#{from_symref_name}"])[0]
            rescue Git::GitExecuteError => e
              to_symref_sha = nil
            end

            # Update local symref
            if to_symref_sha.nil? or not from_symref_sha.eql? to_symref_sha
              puts "Update symref: #{from}[#{from_symref_sha}] != #{to}[#{to_symref_sha}]".yellow
              git.symbolic_ref(["#{from_symref_name}", "#{from_symref_sha}"])
            else
              puts "Skip updating symref: #{from}[#{from_symref_sha}] = #{to}[#{to_symref_sha}]"
            end
          end
        end
      end
    rescue Git::GitExecuteError => e
      puts "[#{DateTime.now} #{from}] Issue with updating symref: #{e}".red
    end
  end

  def sync!
    puts "Sync '#{from}' to '#{to} (dry run: #{dry_run})".blue
    result = true
    pid = nil

    should_clone = true
    should_clone = (Dir.entries(to).count <= 2) if File.exists?(to)
    if not should_clone and not File.exists?(File.join(to, "objects"))
      handle_corrupted
      should_clone = true
    end

    if should_clone
      puts "[#{DateTime.now} #{to}] Cloning ..."
      if not dry_run
        pid = Process.fork {
          Git.clone(from, File.basename(to), path: File.dirname(to), mirror: true)
        }
      end
    else
      puts "[#{DateTime.now} #{to}] Updating ..."
      if not dry_run
        pid = Process.fork {
          add_remote = true

          begin
            # Look for the remove and if it needs to be updated
            git.remotes.each do |remote|
              next if remote.name != "gitsync"

              if remote.url != from
                git.remove_remote("gitsync")
              else
                add_remote = false
                break
              end
            end

            if add_remote
              git.add_remote("gitsync", from, :mirror => 'fetch')
            end

            git.fetch("gitsync", :prune => true)
          rescue Git::GitExecuteError => e
            puts "[#{DateTime.now} #{to}] Issue with fetching: #{e}".red
            check_corrupted
          end

          update_symref(from, to)
        }
      end
    end

    if pid
      begin
        Timeout.timeout(timeout) {
          Process.waitpid(pid)

          # If there was any issue in the sync, add back to the queue
          status = $?.exitstatus
          if status != 0
            STDERR.puts "Fetch process #{pid} failed: #{status}".red
            case status
            when EXIT_CORRUPTED
              result = false
            else
              STDERR.puts "Exit code #{status} not handled"
            end
          end
        }

      # In case of timeout, send a series of SIGTERM and SIGKILL
      rescue Timeout::Error
        STDERR.puts "Timeout for #{to}: sending TERM to #{pid}".red
        Process.kill("TERM", pid)

        begin
          Timeout.timeout(20) {
            Process.waitpid(pid)
          }
        rescue Timeout::Error
          STDERR.puts "Timeout for #{to}: sending KILL to #{pid}".red
          Process.kill("KILL", pid)
          Process.waitpid(pid)
        end

        # Mark as failed in case of timeout
        result = false
      end
    end

    # Add ourselves back at the end of the queue in case of failure
    if not result
      @queue << self
    end

    puts "[#{DateTime.now} #{to}] Done ..."
    @done = true

    result
  end
end
