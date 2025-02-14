# frozen_string_literal: true

module Haystack
  module Rails
    module ActiveJobExtensions
      def perform_now
        if !Haystack.initialized? || already_supported_by_haystack_integration?
          super
        else
          HaystackReporter.record(self) do
            super
          end
        end
      end

      def already_supported_by_haystack_integration?
        Haystack.configuration.rails.skippable_job_adapters.include?(self.class.queue_adapter.class.to_s)
      end

      class HaystackReporter
        OP_NAME = "queue.active_job"
        SPAN_ORIGIN = "auto.queue.active_job"

        class << self
          def record(job, &block)
            Haystack.with_scope do |scope|
              begin
                scope.set_transaction_name(job.class.name, source: :task)
                transaction =
                  if job.is_a?(::Haystack::SendEventJob)
                    nil
                  else
                    Haystack.start_transaction(
                      name: scope.transaction_name,
                      source: scope.transaction_source,
                      op: OP_NAME,
                      origin: SPAN_ORIGIN
                    )
                  end

                scope.set_span(transaction) if transaction

                yield.tap do
                  finish_haystack_transaction(transaction, 200)
                end
              rescue Exception => e # rubocop:disable Lint/RescueException
                finish_haystack_transaction(transaction, 500)

                Haystack::Rails.capture_exception(
                  e,
                  extra: haystack_context(job),
                  tags: {
                    job_id: job.job_id,
                    provider_job_id: job.provider_job_id
                  }
                )
                raise
              end
            end
          end

          def finish_haystack_transaction(transaction, status)
            return unless transaction

            transaction.set_http_status(status)
            transaction.finish
          end

          def haystack_context(job)
            {
              active_job: job.class.name,
              arguments: haystack_serialize_arguments(job.arguments),
              scheduled_at: job.scheduled_at,
              job_id: job.job_id,
              provider_job_id: job.provider_job_id,
              locale: job.locale
            }
          end

          def haystack_serialize_arguments(argument)
            case argument
            when Hash
              argument.transform_values { |v| haystack_serialize_arguments(v) }
            when Array, Enumerable
              argument.map { |v| haystack_serialize_arguments(v) }
            when ->(v) { v.respond_to?(:to_global_id) }
              argument.to_global_id.to_s rescue argument
            else
              argument
            end
          end
        end
      end
    end
  end
end
