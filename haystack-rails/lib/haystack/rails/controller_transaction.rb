# frozen_string_literal: true

module Haystack
  module Rails
    module ControllerTransaction
      SPAN_ORIGIN = "auto.view.rails"

      def self.included(base)
        base.prepend_around_action(:haystack_around_action)
      end

      private

      def haystack_around_action
        if Haystack.initialized?
          transaction_name = "#{self.class}##{action_name}"
          Haystack.get_current_scope.set_transaction_name(transaction_name, source: :view)
          Haystack.with_child_span(op: "view.process_action.action_controller", description: transaction_name, origin: SPAN_ORIGIN) do |child_span|
            if child_span
              begin
                result = yield
              ensure
                child_span.set_http_status(response.status)
                child_span.set_data(:format, request.format)
                child_span.set_data(:method, request.method)

                pii = Haystack.configuration.send_default_pii
                child_span.set_data(:path, pii ? request.fullpath : request.filtered_path)
                child_span.set_data(:params, pii ? request.params : request.filtered_parameters)
              end

              result
            else
              yield
            end
          end
        else
          yield
        end
      end
    end
  end
end
