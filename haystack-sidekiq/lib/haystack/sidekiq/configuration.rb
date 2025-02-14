# frozen_string_literal: true

module Haystack
  class Configuration
    attr_reader :sidekiq

    add_post_initialization_callback do
      @sidekiq = Haystack::Sidekiq::Configuration.new
      @excluded_exceptions = @excluded_exceptions.concat(Haystack::Sidekiq::IGNORE_DEFAULT)
    end
  end

  module Sidekiq
    IGNORE_DEFAULT = [
      "Sidekiq::JobRetry::Skip",
      "Sidekiq::JobRetry::Handled"
    ]

    class Configuration
      # Set this option to true if you want Haystack to only capture the last job
      # retry if it fails.
      attr_accessor :report_after_job_retries

      def initialize
        @report_after_job_retries = false
      end
    end
  end
end
