require 'slugforge/models/tag_manager'

module Slugforge
  module Commands
    class Project < Slugforge::SubCommand
      desc 'list', 'list available projects'
      def list
        logger.say "Available projects:"

        tag_manager.projects.map do |project|

          out = [set_color(project, :green)]
          pc = tag_manager.slug_for_tag(project, 'production-current')
          out << "(production-current: #{set_color(pc, :yellow)})" unless pc.nil?
          out
        end.sort.each do |o|
          logger.say "  #{o * ' '}"
        end
      end
    end
  end
end
