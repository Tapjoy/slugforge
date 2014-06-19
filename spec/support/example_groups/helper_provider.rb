require 'active_support/concern'

module HelperProvider
  extend ActiveSupport::Concern

  included do
    let(:helpers) { SpecHelpers.new }
  end
end

