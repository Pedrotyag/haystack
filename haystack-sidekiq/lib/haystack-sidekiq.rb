# frozen_string_literal: true

require "sidekiq"
require "haystack-ruby"
require "haystack/integrable"
require "haystack/sidekiq/version"
require "haystack/sidekiq/configuration"
require "haystack/sidekiq/error_handler"
require "haystack/sidekiq/haystack_context_middleware"

module Haystack
  module Sidekiq
    extend Haystack::Integrable

    register_integration name: "sidekiq", version: Haystack::Sidekiq::VERSION

    if defined?(::Rails::Railtie)
      class Railtie < ::Rails::Railtie
        config.after_initialize do
          next unless Haystack.initialized? && defined?(::Haystack::Rails)

          Haystack.configuration.rails.skippable_job_adapters << "ActiveJob::QueueAdapters::SidekiqAdapter"
        end
      end
    end
  end
end

Sidekiq.configure_server do |config|
  config.error_handlers << Haystack::Sidekiq::ErrorHandler.new
  config.server_middleware do |chain|
    chain.add Haystack::Sidekiq::HaystackContextServerMiddleware
  end
  config.client_middleware do |chain|
    chain.add Haystack::Sidekiq::HaystackContextClientMiddleware
  end
end

Sidekiq.configure_client do |config|
  config.client_middleware do |chain|
    chain.add Haystack::Sidekiq::HaystackContextClientMiddleware
  end
end

# patches
require "haystack/sidekiq/cron/job"
require "haystack/sidekiq-scheduler/scheduler"
