module Haystack
  module HaystackJsHelper
    def haystack_script(dsn:)
      <<~HTML
        <%= javascript_include_tag 'haystack/bundle.tracing.replay.min.js' %>

        <script>
          Sentry.init({
            dsn: "#{dsn}",
            environment: "#{Rails.env}",
            tracesSampleRate: 1,
            replaysSessionSampleRate: 0,
            replaysOnErrorSampleRate: 1,
            integrations: [
              Sentry.replayIntegration({
                maskAllText: false,
                blockAllMedia: true,
              }),
              Sentry.browserTracingIntegration(),
            ],
            beforeSend(event, hint) {
              if (event.level === "error") {
                event.contexts = event.contexts || {};
                event.contexts.trace = hint?.traceContext || event.contexts.trace || {};
              }

              return event;
            },
          });

          Sentry.setUser({
            id: #{current_user&.id},
            email: "#{current_user&.email}",
            username: "#{current_user&.name}",
          });
        </script>
      HTML
    end
  end
end
