# frozen_string_literal: true

require "haystack/rails/capture_exceptions"
require "haystack/rails/rescued_exception_interceptor"
require "haystack/rails/backtrace_cleaner"

module Haystack
  class Railtie < ::Rails::Railtie
    # middlewares can't be injected after initialize
    initializer "haystack.use_rack_middleware" do |app|
      # placed after all the file-sending middlewares so we can avoid unnecessary transactions
      app.config.middleware.insert_after ActionDispatch::ShowExceptions, Haystack::Rails::CaptureExceptions
      # need to place as close to DebugExceptions as possible to intercept most of the exceptions, including those raised by middlewares
      app.config.middleware.insert_after ActionDispatch::DebugExceptions, Haystack::Rails::RescuedExceptionInterceptor
    end

    # because the extension works by registering the around_perform callback, it should always be run
    # before the application is eager-loaded (before user's jobs register their own callbacks)
    # See https://github.com/gethaystack/haystack-ruby/issues/1249#issuecomment-853871871 for the detail explanation
    initializer "haystack.extend_active_job", before: :eager_load! do |app|
      ActiveSupport.on_load(:active_job) do
        require "haystack/rails/active_job"
        prepend Haystack::Rails::ActiveJobExtensions
      end
    end

    initializer "haystack.extend_action_cable", before: :eager_load! do |app|
      ActiveSupport.on_load(:action_cable_connection) do
        require "haystack/rails/action_cable"
        prepend Haystack::Rails::ActionCableExtensions::Connection
      end

      ActiveSupport.on_load(:action_cable_channel) do
        require "haystack/rails/action_cable"
        include Haystack::Rails::ActionCableExtensions::Channel::Subscriptions
        prepend Haystack::Rails::ActionCableExtensions::Channel::Actions
      end
    end

    config.after_initialize do |app|
      next unless Haystack.initialized?

      configure_project_root
      configure_trusted_proxies
      configure_cron_timezone
      extend_controller_methods if defined?(ActionController)
      patch_background_worker if defined?(ActiveRecord)
      override_streaming_reporter if defined?(ActionView)
      setup_backtrace_cleanup_callback
      inject_breadcrumbs_logger
      activate_tracing

      register_error_subscriber(app) if ::Rails.version.to_f >= 7.0 && Haystack.configuration.rails.register_error_subscriber
    end

    runner do
      next unless Haystack.initialized?
      Haystack.configuration.background_worker_threads = 0

      at_exit do
        # TODO: Add a condition for Rails 7.1 to avoid confliction with https://github.com/rails/rails/pull/44999
        if $ERROR_INFO && !($ERROR_INFO.is_a?(SystemExit) && $ERROR_INFO.success?)
          Haystack::Rails.capture_exception($ERROR_INFO, tags: { source: "runner" })
        end
      end
    end

    def configure_project_root
      Haystack.configuration.project_root = ::Rails.root.to_s
    end

    def configure_trusted_proxies
      Haystack.configuration.trusted_proxies += Array(::Rails.application.config.action_dispatch.trusted_proxies)
    end

    def configure_cron_timezone
      tz_info = ::ActiveSupport::TimeZone.find_tzinfo(::Rails.application.config.time_zone)
      Haystack.configuration.cron.default_timezone = tz_info.name
    end

    def extend_controller_methods
      require "haystack/rails/controller_methods"
      require "haystack/rails/controller_transaction"
      require "haystack/rails/overrides/streaming_reporter"

      ActiveSupport.on_load :action_controller do
        include Haystack::Rails::ControllerMethods
        include Haystack::Rails::ControllerTransaction
        ActionController::Live.send(:prepend, Haystack::Rails::Overrides::StreamingReporter)
      end
    end

    def patch_background_worker
      require "haystack/rails/background_worker"
    end

    def inject_breadcrumbs_logger
      if Haystack.configuration.breadcrumbs_logger.include?(:active_support_logger)
        require "haystack/rails/breadcrumb/active_support_logger"
        Haystack::Rails::Breadcrumb::ActiveSupportLogger.inject(Haystack.configuration.rails.active_support_logger_subscription_items)
      end

      if Haystack.configuration.breadcrumbs_logger.include?(:monotonic_active_support_logger)
        return warn "Usage of `monotonic_active_support_logger` require a version of Rails >= 6.1, please upgrade your Rails version or use another logger" if ::Rails.version.to_f < 6.1

        require "haystack/rails/breadcrumb/monotonic_active_support_logger"
        Haystack::Rails::Breadcrumb::MonotonicActiveSupportLogger.inject
      end
    end

    def setup_backtrace_cleanup_callback
      backtrace_cleaner = Haystack::Rails::BacktraceCleaner.new

      Haystack.configuration.backtrace_cleanup_callback ||= lambda do |backtrace|
        backtrace_cleaner.clean(backtrace)
      end
    end

    def override_streaming_reporter
      require "haystack/rails/overrides/streaming_reporter"

      ActiveSupport.on_load :action_view do
        ActionView::StreamingTemplateRenderer::Body.send(:prepend, Haystack::Rails::Overrides::StreamingReporter)
      end
    end

    def activate_tracing
      if Haystack.configuration.tracing_enabled? && Haystack.configuration.instrumenter == :haystack
        subscribers = Haystack.configuration.rails.tracing_subscribers
        Haystack::Rails::Tracing.register_subscribers(subscribers)
        Haystack::Rails::Tracing.subscribe_tracing_events
        Haystack::Rails::Tracing.patch_active_support_notifications
      end
    end

    def register_error_subscriber(app)
      require "haystack/rails/error_subscriber"
      app.executor.error_reporter.subscribe(Haystack::Rails::ErrorSubscriber.new)
    end
  end
end
