# frozen_string_literal: true

module Haystack
  module Rack
    class CaptureExceptions
      ERROR_EVENT_ID_KEY = "haystack.error_event_id"
      MECHANISM_TYPE = "rack"
      SPAN_ORIGIN = "auto.http.rack"

      def initialize(app)
        @app = app
      end

      def call(env)
        return @app.call(env) unless Haystack.initialized?

        # make sure the current thread has a clean hub
        Haystack.clone_hub_to_current_thread

        Haystack.with_scope do |scope|
          Haystack.with_session_tracking do
            scope.clear_breadcrumbs
            scope.set_transaction_name(env["PATH_INFO"], source: :url) if env["PATH_INFO"]
            scope.set_rack_env(env)

            transaction = start_transaction(env, scope)
            scope.set_span(transaction) if transaction

            begin
              response = @app.call(env)
            rescue Haystack::Error
              finish_transaction(transaction, 500)
              raise # Don't capture Haystack errors
            rescue Exception => e
              capture_exception(e, env)
              finish_transaction(transaction, 500)
              raise
            end

            exception = collect_exception(env)
            capture_exception(exception, env) if exception

            finish_transaction(transaction, response[0])

            response
          end
        end
      end

      private

      def collect_exception(env)
        env["rack.exception"] || env["sinatra.error"]
      end

      def transaction_op
        "http.server"
      end

      def capture_exception(exception, env)
        Haystack.capture_exception(exception, hint: { mechanism: mechanism }).tap do |event|
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

        transaction = Haystack.continue_trace(env, **options)
        Haystack.start_transaction(transaction: transaction, custom_sampling_context: { env: env }, **options)
      end


      def finish_transaction(transaction, status_code)
        return unless transaction

        transaction.set_http_status(status_code)
        transaction.finish
      end

      def mechanism
        Haystack::Mechanism.new(type: MECHANISM_TYPE, handled: false)
      end
    end
  end
end
