require 'colored'
require 'json'

class GitSync::Event

  def initialize(src)
    @event = JSON.parse(src)
  end

  def type
    @event["type"]
  end

  def project_name
    return event["change"]["project"] if event["change"]
    return event["refUpdate"]["project"] if event["refUpdate"]
    return event["projectName"] if event["projectName"]
    nil
  end

  def [](key)
    @event[key]
  end
end
