# frozen_string_literal: true

module Haystack
  module Rails
    class RescuedExceptionInterceptor
      def initialize(app)
        @app = app
      end

      def call(env)
        return @app.call(env) unless Haystack.initialized?

        begin
          @app.call(env)
        rescue => e
          env["haystack.rescued_exception"] = e if report_rescued_exceptions?
          raise e
        end
      end

      def report_rescued_exceptions?
        # In rare edge cases, `Haystack.configuration` might be `nil` here.
        # Hence, we use a safe navigation and fallback to a reasonable default
        # of `true` in case the configuration couldn't be loaded.
        # See https://github.com/gethaystack/haystack-ruby/issues/2386
        report_rescued_exceptions = Haystack.configuration&.rails&.report_rescued_exceptions
        return report_rescued_exceptions unless report_rescued_exceptions.nil?

        # `true` is the default for `report_rescued_exceptions`, as specified in
        # `haystack-rails/lib/haystack/rails/configuration.rb`.
        true
      end
    end
  end
end
