# frozen_string_literal: true

module Haystack
  module Rails
    module Overrides
      module StreamingReporter
        def log_error(exception)
          Haystack::Rails.capture_exception(exception)
          super
        end
      end

      module OldStreamingReporter
        def self.included(base)
          base.send(:alias_method_chain, :log_error, :raven)
        end

        def log_error_with_raven(exception)
          Haystack::Rails.capture_exception(exception)
          log_error_without_raven(exception)
        end
      end
    end
  end
end
