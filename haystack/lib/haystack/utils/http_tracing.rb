# frozen_string_literal: true

module Haystack
  module Utils
    module HttpTracing
      def set_span_info(haystack_span, request_info, response_status)
        haystack_span.set_description("#{request_info[:method]} #{request_info[:url]}")
        haystack_span.set_data(Span::DataConventions::URL, request_info[:url])
        haystack_span.set_data(Span::DataConventions::HTTP_METHOD, request_info[:method])
        haystack_span.set_data(Span::DataConventions::HTTP_QUERY, request_info[:query]) if request_info[:query]
        haystack_span.set_data(Span::DataConventions::HTTP_STATUS_CODE, response_status)
      end

      def set_propagation_headers(req)
        Haystack.get_trace_propagation_headers&.each { |k, v| req[k] = v }
      end

      def record_haystack_breadcrumb(request_info, response_status)
        crumb = Haystack::Breadcrumb.new(
          level: :info,
          category: self.class::BREADCRUMB_CATEGORY,
          type: "info",
          data: { status: response_status, **request_info }
        )

        Haystack.add_breadcrumb(crumb)
      end

      def record_haystack_breadcrumb?
        Haystack.initialized? && Haystack.configuration.breadcrumbs_logger.include?(:http_logger)
      end

      def propagate_trace?(url)
        url &&
          Haystack.initialized? &&
          Haystack.configuration.propagate_traces &&
          Haystack.configuration.trace_propagation_targets.any? { |target| url.match?(target) }
      end

      # Kindly borrowed from Rack::Utils
      def build_nested_query(value, prefix = nil)
        case value
        when Array
          value.map { |v|
            build_nested_query(v, "#{prefix}[]")
          }.join("&")
        when Hash
          value.map { |k, v|
            build_nested_query(v, prefix ? "#{prefix}[#{k}]" : k)
          }.delete_if(&:empty?).join("&")
        when nil
          URI.encode_www_form_component(prefix)
        else
          raise ArgumentError, "value must be a Hash" if prefix.nil?
          "#{URI.encode_www_form_component(prefix)}=#{URI.encode_www_form_component(value)}"
        end
      end
    end
  end
end
