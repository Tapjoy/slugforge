# Make things work while testing crap
git_path = File.expand_path('../../.git', __FILE__)
if File.exists?(git_path)
  slugforge_path = File.expand_path('../../lib', __FILE__)
  $:.unshift(slugforge_path)

  begin
    require 'pry-debugger'
  rescue LoadError
  end
end

require 'active_support/core_ext/string/inflections'
require 'active_support/notifications'

require 'slugforge/configuration'
require 'slugforge/cli'
require 'slugforge/version'

