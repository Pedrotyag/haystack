# frozen_string_literal: true

require "haystack/rails/tracing/abstract_subscriber"
require "haystack/rails/instrument_payload_cleanup_helper"

module Haystack
  module Rails
    module Tracing
      class ActionControllerSubscriber < AbstractSubscriber
        extend InstrumentPayloadCleanupHelper

        EVENT_NAMES = ["process_action.action_controller"].freeze
        OP_NAME = "view.process_action.action_controller"
        SPAN_ORIGIN = "auto.view.rails"

        def self.subscribe!
          Haystack.logger.warn <<~MSG
            DEPRECATION WARNING: haystack-rails has changed its approach on controller span recording and #{self.name} is now depreacted.
            Please stop using or referencing #{self.name} as it will be removed in the next major release.
          MSG

          subscribe_to_event(EVENT_NAMES) do |event_name, duration, payload|
            controller = payload[:controller]
            action = payload[:action]

            record_on_current_span(
              op: OP_NAME,
              origin: SPAN_ORIGIN,
              start_timestamp: payload[START_TIMESTAMP_NAME],
              description: "#{controller}##{action}",
              duration: duration
            ) do |span|
              payload = payload.dup
              cleanup_data(payload)
              span.set_data(:payload, payload)
              span.set_http_status(payload[:status])
            end
          end
        end
      end
    end
  end
end
