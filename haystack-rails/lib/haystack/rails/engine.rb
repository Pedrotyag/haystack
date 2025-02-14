# frozen_string_literal: true

require "haystack/rails/middleware/injector"

module Haystack
  class Engine < ::Rails::Engine
    isolate_namespace Haystack

    initializer 'haystack.add_middleware', before: 'ActionDispatch::ShowExceptions' do |app|
      app.middleware.insert_before ActionDispatch::ShowExceptions, Haystack::Rails::Middleware::Injector
    end

    initializer 'haystack.assets.precompile' do |app|
      app.config.assets.precompile += %w[haystack/bundle.tracing.replay.min.js]
    end
  end
end
