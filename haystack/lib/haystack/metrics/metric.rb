# frozen_string_literal: true

module Haystack
  module Metrics
    class Metric
      def add(value)
        raise NotImplementedError
      end

      def serialize
        raise NotImplementedError
      end

      def weight
        raise NotImplementedError
      end
    end
  end
end
