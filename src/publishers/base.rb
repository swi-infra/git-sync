
class GitSync::Publisher::Base

  def initialize()

  end

  def publish(event)
    raise NotImplementedError, "Implement this method in a child class"
  end

end

