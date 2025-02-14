# frozen_string_literal: true

require "bundler/setup"
begin
  require "debug/prelude"
rescue LoadError
end

require "haystack"
require 'rspec/retry'

require 'simplecov'

SimpleCov.start do
  project_name "haystack-rails"
  root File.join(__FILE__, "../../../")
  coverage_dir File.join(__FILE__, "../../coverage")
end


if ENV["CI"]
  require 'simplecov-cobertura'
  SimpleCov.formatter = SimpleCov::Formatter::CoberturaFormatter
end

# this already requires the sdk
require "dummy/test_rails_app/app"
# need to be required after rails is loaded from the above
require "rspec/rails"

DUMMY_DSN = 'http://12345:67890@haystack.localdomain/haystack/42'

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  config.after :each do
    Haystack::Rails::Tracing.unsubscribe_tracing_events
    expect(Haystack::Rails::Tracing.subscribed_tracing_events).to be_empty
    Haystack::Rails::Tracing.remove_active_support_notifications_patch
  end

  config.before :each do
    # Make sure we reset the env in case something leaks in
    ENV.delete('HAYSTACK_DSN')
    ENV.delete('HAYSTACK_CURRENT_ENV')
    ENV.delete('HAYSTACK_ENVIRONMENT')
    ENV.delete('HAYSTACK_RELEASE')
    ENV.delete('RAILS_ENV')
    ENV.delete('RACK_ENV')
  end

  config.include ActiveJob::TestHelper, type: :job
end

def reload_send_event_job
  Haystack.send(:remove_const, "SendEventJob") if defined?(Haystack::SendEventJob)
  expect(defined?(Haystack::SendEventJob)).to eq(nil)
  load File.join(Dir.pwd, "app", "jobs", "haystack", "send_event_job.rb")
end
