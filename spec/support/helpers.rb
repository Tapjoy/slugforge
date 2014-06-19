class SpecHelpers
  def self.class_option(*); end
  def self.source_root(*); end

  include Slugforge::Helper

  def initialize(args=[], options={}, config={})
    @config = Slugforge::Configuration.new(options)
  end

  def config; @config; end

  def options; {}; end

  def metadata
    parse_metadata_file
  end
end
