# frozen_string_literal: true

require "logger"

module Haystack
  class Logger < ::Logger
    LOG_PREFIX = "** [Haystack] "
    PROGNAME   = "haystack"

    def initialize(*)
      super
      @level = ::Logger::INFO
      original_formatter = ::Logger::Formatter.new
      @default_formatter = proc do |severity, datetime, _progname, msg|
        msg = "#{LOG_PREFIX}#{msg}"
        original_formatter.call(severity, datetime, PROGNAME, msg)
      end
    end
  end
end
