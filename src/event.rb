require 'colored'
require 'json'

class GitSync::Event
  attr_reader :event
  attr_accessor :sync_count

  def initialize(src)
    @event = JSON.parse(src)
    @sync_count = 0
  end

  def to_s
    str = "event<#{type}>[#{project_name}]"
    str += "{#{ref}}" if ref
    str
  end

  def type
    @event["type"]
  end

  def project_name
    return @event["change"]["project"] if @event["change"]
    return @event["refUpdate"]["project"] if @event["refUpdate"]
    return @event["projectName"] if @event["projectName"]
    nil
  end

  def ref
    return @event["refName"] if type == "change-merged"
    return @event["patchSet"]["ref"] if @event["patchSet"]
    return @event["refUpdate"]["refName"] if @event["refUpdate"]
    nil
  end

  def revision
    return @event["newRev"] if @event["newRev"]
    return @event["patchSet"]["revision"] if @event["patchSet"]
    return @event["refUpdate"]["newRev"] if @event["refUpdate"]
    nil
  end

  def [](key)
    @event[key]
  end

  def as_json
    JSON.dump(@event)
  end

  def check_updated(source)
    r = ref
    rev = revision
    if r and rev
      return source.check_ref(r, rev)
    end

    true
  end
end
