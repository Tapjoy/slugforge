require 'slugforge/build'

module Slugforge
  module Commands
    class Build < Slugforge::Group
      def build_project
        invoke Slugforge::Build::BuildProject
      end

      def export_upstart
        invoke Slugforge::Build::ExportUpstart
      end

      def package
        invoke Slugforge::Build::Package
      end
    end
  end
end

