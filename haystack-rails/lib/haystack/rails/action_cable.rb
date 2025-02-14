# frozen_string_literal: true

module Haystack
  module Rails
    module ActionCableExtensions
      class ErrorHandler
        OP_NAME = "websocket.server"
        SPAN_ORIGIN = "auto.http.rails.actioncable"

        class << self
          def capture(connection, transaction_name:, extra_context: nil, &block)
            return block.call unless Haystack.initialized?
            # ActionCable's ConnectionStub (for testing) doesn't implement the exact same interfaces as Connection::Base.
            # One thing that's missing is `env`. So calling `connection.env` direclty will fail in test environments when `stub_connection` is used.
            # See https://github.com/gethaystack/haystack-ruby/pull/1684 for more information.
            env = connection.respond_to?(:env) ? connection.env : {}

            Haystack.with_scope do |scope|
              scope.set_rack_env(env)
              scope.set_context("action_cable", extra_context) if extra_context
              scope.set_transaction_name(transaction_name, source: :view)
              transaction = start_transaction(env, scope)
              scope.set_span(transaction) if transaction

              begin
                result = block.call
                finish_transaction(transaction, 200)
                result
              rescue Exception => e # rubocop:disable Lint/RescueException
                Haystack::Rails.capture_exception(e)
                finish_transaction(transaction, 500)

                raise
              end
            end
          end

          def start_transaction(env, scope)
            options = {
              name: scope.transaction_name,
              source: scope.transaction_source,
              op: OP_NAME,
              origin: SPAN_ORIGIN
            }

            transaction = Haystack.continue_trace(env, **options)
            Haystack.start_transaction(transaction: transaction, **options)
          end

          def finish_transaction(transaction, status_code)
            return unless transaction

            transaction.set_http_status(status_code)
            transaction.finish
          end
        end
      end

      module Connection
        private

        def handle_open
          ErrorHandler.capture(self, transaction_name: "#{self.class.name}#connect") do
            super
          end
        end

        def handle_close
          ErrorHandler.capture(self, transaction_name: "#{self.class.name}#disconnect") do
            super
          end
        end
      end

      module Channel
        module Subscriptions
          def self.included(base)
            base.class_eval do
              set_callback :subscribe, :around, ->(_, block) { haystack_capture(:subscribed, &block) }, prepend: true
              set_callback :unsubscribe, :around, ->(_, block) { haystack_capture(:unsubscribed, &block) }, prepend: true
            end
          end

          private

          def haystack_capture(hook, &block)
            extra_context = { params: params }

            ErrorHandler.capture(connection, transaction_name: "#{self.class.name}##{hook}", extra_context: extra_context, &block)
          end
        end

        module Actions
          private

          def dispatch_action(action, data)
            extra_context = { params: params, data: data }

            ErrorHandler.capture(connection, transaction_name: "#{self.class.name}##{action}", extra_context: extra_context) do
              super
            end
          end
        end
      end
    end
  end
end
