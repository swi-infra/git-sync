class GitSync::Source::Base
  attr_accessor :timeout, :dry_run

  def initialize(publishers)
    @timeout = 90*60
    @dry_run = false
    @publishers = publishers
  end

  def publish(event)
    @publishers.each do |p|
      p.publish(event)
    end
  end
end

