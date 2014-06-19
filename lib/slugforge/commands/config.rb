module Slugforge
  module Commands
    class Config < Slugforge::SubCommand
      desc 'show', 'Print current configuration options'
      def show
        if json?
          logger.say_json config.values
        else
          logger.say "The following configuration options are in use:"
          rows = config.values.map { |name, value| [name, value] }
          print_table(rows, :indent => 4)

          unless config.slugins.empty?
            logger.say "Slugins detected:"
            rows = config.slugins.map do |(name, slugin)|
              [name, slugin.spec.version, slugin.enabled ? 'enabled' : 'disabled']
            end
            print_table(rows, :indent => 4)
          end
        end
      end
    end
  end
end
