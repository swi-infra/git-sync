require 'colored'
require 'json'

class GitSync::Event
  attr_reader :event

  def initialize(src)
    @event = JSON.parse(src)
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
    return @event["change"]["ref"] if @event["change"]
    return @event["refUpdate"]["refName"] if @event["refUpdate"]
    nil
  end

  def [](key)
    @event[key]
  end

  def as_json
    JSON.dump(@event)
  end
end
