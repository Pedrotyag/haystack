# frozen_string_literal: true

module Haystack
  module LoggingHelper
    def log_error(message, exception, debug: false)
      message = "#{message}: #{exception.message}"
      message += "\n#{exception.backtrace.join("\n")}" if debug

      @logger.error(LOGGER_PROGNAME) do
        message
      end
    end

    def log_debug(message)
      @logger.debug(LOGGER_PROGNAME) { message }
    end

    def log_warn(message)
      @logger.warn(LOGGER_PROGNAME) { message }
    end
  end
end
