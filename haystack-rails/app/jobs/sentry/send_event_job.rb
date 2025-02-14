# frozen_string_literal: true

if defined?(ActiveJob)
  module Haystack
    parent_job =
      if defined?(::ApplicationJob) && ::ApplicationJob.ancestors.include?(::ActiveJob::Base)
        ::ApplicationJob
      else
        ::ActiveJob::Base
      end

    class SendEventJob < parent_job
      # the event argument is usually large and creates noise
      self.log_arguments = false if respond_to?(:log_arguments=)

      # this will prevent infinite loop when there's an issue deserializing HaystackJob
      if respond_to?(:discard_on)
        discard_on ActiveJob::DeserializationError
      else
        # mimic what discard_on does for Rails 5.0
        rescue_from ActiveJob::DeserializationError do |exception|
          logger.error "Discarded #{self.class} due to a #{exception}. The original exception was #{exception.cause.inspect}."
        end
      end

      def perform(event, hint = {})
        Haystack.send_event(event, hint)
      end
    end
  end
else
  module Haystack
    class SendEventJob; end
  end
end
