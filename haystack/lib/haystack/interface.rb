# frozen_string_literal: true

module Haystack
  class Interface
    # @return [Hash]
    def to_hash
      Hash[instance_variables.map { |name| [name[1..-1].to_sym, instance_variable_get(name)] }]
    end
  end
end

require "haystack/interfaces/exception"
require "haystack/interfaces/request"
require "haystack/interfaces/single_exception"
require "haystack/interfaces/stacktrace"
require "haystack/interfaces/threads"
require "haystack/interfaces/mechanism"
