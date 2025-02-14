# frozen_string_literal: true

module Haystack
  module Rails
    module ControllerMethods
      def capture_message(message, options = {})
        with_request_scope do
          Haystack::Rails.capture_message(message, **options)
        end
      end

      def capture_exception(exception, options = {})
        with_request_scope do
          Haystack::Rails.capture_exception(exception, **options)
        end
      end

      private

      def with_request_scope
        Haystack.with_scope do |scope|
          scope.set_rack_env(request.env)
          yield
        end
      end
    end
  end
end
