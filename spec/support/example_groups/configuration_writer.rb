require 'active_support/concern'

module ConfigurationWriter
  extend ActiveSupport::Concern

  included do
    def write_config_file(configuration)
      File.open(Slugforge::Configuration.configuration_files.first, "w+") do |f|
        f.write configuration.to_yaml
      end
    end

    # Only do this configuration when specifically requested by setting :config => true on the example group
    before(:each, :config => true) do
      write_config_file 'aws' => {
        'access_key' => 'zzz-access-key',
        'secret_key' => 'zzz-secret-key',
        'slug_bucket' => 'tj-slugforge'
      }

      helpers.s3.directories.create({key: 'tj-slugforge'})
    end
  end
end
