# frozen_string_literal: true

module Haystack
  module Rails
    class CaptureExceptions < Haystack::Rack::CaptureExceptions
      RAILS_7_1 = Gem::Version.new(::Rails.version) >= Gem::Version.new("7.1.0.alpha")
      SPAN_ORIGIN = "auto.http.rails"

      def initialize(_)
        super

        if Haystack.initialized?
          @assets_regexp = Haystack.configuration.rails.assets_regexp
        end
      end

      private

      def collect_exception(env)
        return nil if env["haystack.already_captured"]
        super || env["action_dispatch.exception"] || env["haystack.rescued_exception"]
      end

      def transaction_op
        "http.server"
      end

      def capture_exception(exception, env)
        # the exception will be swallowed by ShowExceptions middleware
        return if show_exceptions?(exception, env) && !Haystack.configuration.rails.report_rescued_exceptions

        Haystack::Rails.capture_exception(exception).tap do |event|
          env[ERROR_EVENT_ID_KEY] = event.event_id if event
        end
      end

      def start_transaction(env, scope)
        options = {
          name: scope.transaction_name,
          source: scope.transaction_source,
          op: transaction_op,
          origin: SPAN_ORIGIN
        }

        if @assets_regexp && scope.transaction_name.match?(@assets_regexp)
          options.merge!(sampled: false)
        end

        transaction = Haystack.continue_trace(env, **options)
        Haystack.start_transaction(transaction: transaction, custom_sampling_context: { env: env }, **options)
      end

      def show_exceptions?(exception, env)
        request = ActionDispatch::Request.new(env)

        if RAILS_7_1
          ActionDispatch::ExceptionWrapper.new(nil, exception).show?(request)
        else
          request.show_exceptions?
        end
      end
    end
  end
end
