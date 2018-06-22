require 'git'

Encoding.default_external = Encoding::UTF_8
Encoding.default_internal = Encoding::UTF_8

module GitSync
  module Source
  end

  module Publisher
  end
end

require 'config.rb'

require 'sources/base.rb'
require 'sources/single.rb'
require 'sources/gerrit.rb'
require 'sources/gerrit_ssh.rb'
require 'sources/gerrit_rabbitmq.rb'

require 'publishers/base.rb'
require 'publishers/rabbitmq.rb'
