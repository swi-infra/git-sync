require 'socket'
require 'json'

class GitSync::Event::Init < GitSync::Event::Base

  def initialize(project_name)
    @event = {
      type: "sync-init",
      projectName: project_name,
      origin: Socket.gethostname
    }

    super(JSON.dump(@event))
  end
end
