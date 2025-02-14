# frozen_string_literal: true

module Haystack
  module Metrics
    class DistributionMetric < Metric
      attr_reader :value

      def initialize(value)
        @value = [value.to_f]
      end

      def add(value)
        @value << value.to_f
      end

      def serialize
        value
      end

      def weight
        value.size
      end
    end
  end
end
