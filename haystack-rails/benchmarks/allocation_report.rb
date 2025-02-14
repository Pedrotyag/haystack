# frozen_string_literal: true

require 'benchmark/ipsa'
require "haystack"
require "haystack/benchmarks/benchmark_transport"
require_relative "application"

TestApp.configure do |config|
  config.middleware.delete ActionDispatch::DebugExceptions
  config.middleware.delete ActionDispatch::ShowExceptions
end

app = create_app do |config|
  config.logger = ::Logger.new(STDOUT)
  config.transport.transport_class = Haystack::BenchmarkTransport
  config.breadcrumbs_logger = [:active_support_logger]
end

app.get("/exception")

report = MemoryProfiler.report do
  app.get("/exception")
end

report.pretty_print

# transport = Haystack.get_current_client.transport
# puts(transport.events.count)
# puts(transport.events.first)
