# frozen_string_literal: true

require "rails"
require "haystack"
require "haystack/integrable"
require "haystack/rails/tracing"
require "haystack/rails/configuration"
require "haystack/rails/engine"
require "haystack/rails/railtie"

module Haystack
  module Rails
    extend Integrable
    register_integration name: "rails", version: Haystack::Rails::VERSION
  end
end
