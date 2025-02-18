# frozen_string_literal: true

require "haystack/rails/tracing/abstract_subscriber"

module Haystack
  module Rails
    module Tracing
      class ActionViewSubscriber < AbstractSubscriber
        EVENT_NAMES = ["render_template.action_view"].freeze
        SPAN_PREFIX = "template."
        SPAN_ORIGIN = "auto.template.rails"

        def self.subscribe!
          subscribe_to_event(EVENT_NAMES) do |event_name, duration, payload|
            record_on_current_span(
              op: SPAN_PREFIX + event_name,
              origin: SPAN_ORIGIN,
              start_timestamp: payload[START_TIMESTAMP_NAME],
              description: payload[:identifier],
              duration: duration
            )
          end
        end
      end
    end
  end
end
