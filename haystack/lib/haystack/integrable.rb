# frozen_string_literal: true

module Haystack
  module Integrable
    def register_integration(name:, version:)
      Haystack.register_integration(name, version)
      @integration_name = name
    end

    def integration_name
      @integration_name
    end

    def capture_exception(exception, **options, &block)
      options[:hint] ||= {}
      options[:hint][:integration] = integration_name

      # within an integration, we usually intercept uncaught exceptions so we set handled to false.
      options[:hint][:mechanism] ||= Haystack::Mechanism.new(type: integration_name, handled: false)

      Haystack.capture_exception(exception, **options, &block)
    end

    def capture_message(message, **options, &block)
      options[:hint] ||= {}
      options[:hint][:integration] = integration_name
      Haystack.capture_message(message, **options, &block)
    end

    def capture_check_in(slug, status, **options, &block)
      options[:hint] ||= {}
      options[:hint][:integration] = integration_name
      Haystack.capture_check_in(slug, status, **options, &block)
    end
  end
end
