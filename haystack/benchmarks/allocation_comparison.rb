# frozen_string_literal: true

require 'benchmark/memory'
require "haystack"
require "haystack/benchmarks/benchmark_transport"

Haystack.init do |config|
  config.logger = ::Logger.new(nil)
  config.dsn = "dummy://12345:67890@haystack.localdomain:3000/haystack/42"
  config.transport.transport_class = Haystack::BenchmarkTransport
  config.breadcrumbs_logger = [:haystack_logger]
end

exception = begin
              1/0
            rescue => exp
              exp
            end

Benchmark.memory do |x|
  x.report("master") { Haystack.capture_exception(exception) }
  x.report("branch") { Haystack.capture_exception(exception) }

  x.compare!
  x.hold!("/tmp/allocation_comparison.json")
end
