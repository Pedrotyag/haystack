require 'haystack'

Haystack.init do |config|
  config.dsn = 'https://2fb45f003d054a7ea47feb45898f7649@o447951.ingest.haystack.io/5434472'
  config.traces_sample_rate = 1.0
  # skips handled exceptions
  config.before_send = lambda do |event, hint|
    handled_errors = Sinatra::Application.errors.keys.grep(Class) # skip status codes
    should_skip = false

    handled_errors.each do |error|
      if hint[:exception].is_a?(error)
        should_skip = true
      end
    end

    event unless should_skip
  end
end

# this needs to be placed **after** SDK is initialized
# see https://github.com/gethaystack/haystack/issues/1778 for more information
require 'sinatra'

use Haystack::Rack::CaptureExceptions

error RuntimeError do
  halt 400, "this error will not be reported"
end

get "/handled_exception" do
  raise "foo"
end

get "/" do
  1/0
end

get "/connect_trace" do
  event = Haystack.capture_message("haystack-trace test")
  event.event_id
end
