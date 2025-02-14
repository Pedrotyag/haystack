# frozen_string_literal: true

module Haystack
  module Metrics
    module Timing
      class << self
        def nanosecond
          time = Haystack.utc_now
          time.to_i * (10 ** 9) + time.nsec
        end

        def microsecond
          time = Haystack.utc_now
          time.to_i * (10 ** 6) + time.usec
        end

        def millisecond
          Haystack.utc_now.to_i * (10 ** 3)
        end

        def second
          Haystack.utc_now.to_i
        end

        def minute
          Haystack.utc_now.to_i / 60.0
        end

        def hour
          Haystack.utc_now.to_i / 3600.0
        end

        def day
          Haystack.utc_now.to_i / (3600.0 * 24.0)
        end

        def week
          Haystack.utc_now.to_i / (3600.0 * 24.0 * 7.0)
        end

        def duration_start
          Process.clock_gettime(Process::CLOCK_MONOTONIC)
        end

        def duration_end(start)
          Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
        end
      end
    end
  end
end
