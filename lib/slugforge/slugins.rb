# Copied from Pry under the terms of the MIT license.
# https://github.com/pry/pry/blob/0f207450a968e9e72b6e8cc8b2c21e7029569d3b/lib/pry/slugins.rb

module Slugforge
  class SluginManager
    PREFIX = /^slugforge-/

    # Placeholder when no associated gem found, displays warning
    class NoSlugin
      def initialize(name)
        @name = name
      end

      def method_missing(*args)
        warn "Warning: The slugin '#{@name}' was not found! (no gem found)"
      end
    end

    class Slugin
      attr_accessor :name, :gem_name, :enabled, :spec, :active

      def initialize(name, gem_name, spec, enabled)
        @name, @gem_name, @enabled, @spec = name, gem_name, enabled, spec
      end

      # Disable a slugin. (prevents slugin from being loaded, cannot
      # disable an already activated slugin)
      def disable!
        self.enabled = false
      end

      # Enable a slugin. (does not load it immediately but puts on
      # 'white list' to be loaded)
      def enable!
        self.enabled = true
      end

      # Load the slugin (require the gem - enables/loads the
      # slugin immediately at point of call, even if slugin is
      # disabled)
      # Does not reload slugin if it's already loaded.
      def load!
        begin
          require gem_name
        rescue LoadError => e
          warn "Found slugin #{gem_name}, but could not require '#{gem_name}.rb'"
          warn e
        rescue => e
          warn "require '#{gem_name}' failed, saying: #{e}"
        end

        self.enabled = true
      end

      # Activate the slugin (run its defined activation method)
      # Does not reactivate if already active.
      def activate!(config)
        return if active?

        if klass = slugin_class
          klass.activate(config) if klass.respond_to?(:activate)
        end

        self.active = true
      end

      alias active? active
      alias enabled? enabled

      private

      def slugin_class
        name = spec.name.gsub(/^slugforge-/, '').camelize
        name = "Slugforge#{name}"
        begin
          name.constantize
        rescue NameError
          warn "Slugin #{gem_name} cannot be activated. Expected module named #{name}."
        end
      end
    end

    def initialize
      @slugins = []
      locate_slugins
    end

    # @return [Hash] A hash with all slugin names (minus the prefix) as
    #   keys and slugin objects as values.
    def slugins
      h = Hash.new { |_, key| NoSlugin.new(key) }
      @slugins.each do |slugin|
        h[slugin.name] = slugin
      end
      h
    end

    # Require all enabled slugins, disabled slugins are skipped.
    def load_slugins
      @slugins.each(&:load!)
    end

    def activate_slugins(config)
      @slugins.each { |s| s.activate!(config) if s.enabled? }
    end

    private

    # Find all installed Pry slugins and store them in an internal array.
    def locate_slugins
      Gem.refresh
      (Gem::Specification.respond_to?(:each) ? Gem::Specification : Gem.source_index.find_name('')).each do |gem|
        next if gem.name !~ PREFIX
        slugin_name = gem.name.split('-', 2).last
        @slugins << Slugin.new(slugin_name, gem.name, gem, true) if !gem_located?(gem.name)
      end
      @slugins
    end

    def gem_located?(gem_name)
      @slugins.any? { |slugin| slugin.gem_name == gem_name }
    end
  end

end
