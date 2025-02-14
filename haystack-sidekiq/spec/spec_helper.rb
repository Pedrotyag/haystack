# frozen_string_literal: true

require "bundler/setup"
begin
  require "debug/prelude"
rescue LoadError
end

# this enables sidekiq's server mode
require "sidekiq/cli"

MIN_SIDEKIQ_6 = Gem::Version.new(Sidekiq::VERSION) >= Gem::Version.new("6.0")
WITH_SIDEKIQ_7 = Gem::Version.new(Sidekiq::VERSION) >= Gem::Version.new("7.0")
WITH_SIDEKIQ_6 = MIN_SIDEKIQ_6 && !WITH_SIDEKIQ_7

require "sidekiq/embedded" if WITH_SIDEKIQ_7

if RUBY_VERSION.to_f >= 2.7 && MIN_SIDEKIQ_6
  require 'sidekiq-cron'
  require 'sidekiq-scheduler'
end

require "haystack-ruby"

require 'simplecov'

SimpleCov.start do
  project_name "haystack-sidekiq"
  root File.join(__FILE__, "../../../")
  coverage_dir File.join(__FILE__, "../../coverage")
end

if ENV["CI"]
  require 'simplecov-cobertura'
  SimpleCov.formatter = SimpleCov::Formatter::CoberturaFormatter
end

require "haystack-sidekiq"

DUMMY_DSN = 'http://12345:67890@haystack.localdomain/haystack/42'

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  config.before :each do
    # Make sure we reset the env in case something leaks in
    ENV.delete('HAYSTACK_DSN')
    ENV.delete('HAYSTACK_CURRENT_ENV')
    ENV.delete('HAYSTACK_ENVIRONMENT')
    ENV.delete('HAYSTACK_RELEASE')
    ENV.delete('sidekiq_ENV')
    ENV.delete('RACK_ENV')
  end

  config.before :all do
    silence_sidekiq
  end
end

def silence_sidekiq
  logger = Logger.new(nil)

  if WITH_SIDEKIQ_7
    Sidekiq.instance_variable_get(:@config).logger = logger
  else
    Sidekiq.logger = logger
  end
end

def build_exception
  1 / 0
rescue ZeroDivisionError => e
  e
end

def build_exception_with_cause(cause = "exception a")
  begin
    raise cause
  rescue
    raise "exception b"
  end
rescue RuntimeError => e
  e
end

def build_exception_with_two_causes
  begin
    begin
      raise "exception a"
    rescue
      raise "exception b"
    end
  rescue
    raise "exception c"
  end
rescue RuntimeError => e
  e
end

def build_exception_with_recursive_cause
  backtrace = []

  exception = double("Exception")
  allow(exception).to receive(:cause).and_return(exception)
  allow(exception).to receive(:message).and_return("example")
  allow(exception).to receive(:backtrace).and_return(backtrace)
  exception
end

class HappyWorker
  include Sidekiq::Worker

  def perform
    crumb = Haystack::Breadcrumb.new(message: "I'm happy!")
    Haystack.add_breadcrumb(crumb)
    Haystack.set_tags mood: 'happy'
  end
end

class SadWorker
  include Sidekiq::Worker

  def perform
    crumb = Haystack::Breadcrumb.new(message: "I'm sad!")
    Haystack.add_breadcrumb(crumb)
    Haystack.set_tags mood: 'sad'

    raise "I'm sad!"
  end
end

class HappyWorkerForCron < HappyWorker; end
class HappyWorkerForScheduler < HappyWorker; end
class HappyWorkerForSchedulerWithTimezone < HappyWorker; end
class EveryHappyWorker < HappyWorker; end
class HappyWorkerWithHumanReadableCron < HappyWorker; end
class HappyWorkerWithSymbolName < HappyWorker; end

class HappyWorkerWithCron < HappyWorker
  include Haystack::Cron::MonitorCheckIns
  haystack_monitor_check_ins
end

class SadWorkerWithCron < SadWorker
  include Haystack::Cron::MonitorCheckIns
  haystack_monitor_check_ins slug: "failed_job", monitor_config: Haystack::Cron::MonitorConfig.from_crontab("5 * * * *")
end

class VerySadWorker
  include Sidekiq::Worker

  def perform
    crumb = Haystack::Breadcrumb.new(message: "I'm very sad!")
    Haystack.add_breadcrumb(crumb)
    Haystack.set_tags mood: 'very sad'

    raise "I'm very sad!"
  end
end

class ReportingWorker
  include Sidekiq::Worker

  def perform
    Haystack.capture_message("I have something to say!")
  end
end

class TagsWorker
  include Sidekiq::Worker

  sidekiq_options tags: ["marvel", "dc"]

  def perform; end
end

def new_processor
  manager =
    case
    when WITH_SIDEKIQ_7
      capsule = Sidekiq.instance_variable_get(:@config).default_capsule
      Sidekiq::Manager.new(capsule)
    when WITH_SIDEKIQ_6
      Sidekiq[:queue] = ['default']
      Sidekiq::Manager.new(Sidekiq)
    else
      Sidekiq::Manager.new({ queues: ['default'] })
    end

  manager.workers.first
end

class SidekiqConfigMock
  include ::Sidekiq
  attr_accessor :options

  def initialize(options = {})
    @options = DEFAULTS.merge(options)
  end

  def fetch(key, default = nil)
    options.fetch(key, default)
  end

  def [](key)
    options[key]
  end
end

module VeryLongOuterModule
  module VeryVeryVeryVeryLongInnerModule
    class Job
    end
  end
end

# Sidekiq 7 has a Config class, but for Sidekiq 6, we'll mock it.
def sidekiq_config(opts)
  WITH_SIDEKIQ_7 ? ::Sidekiq::Config.new(opts) : SidekiqConfigMock.new(opts)
end

def execute_worker(processor, klass, **options)
  klass_options = klass.sidekiq_options_hash || {}
  # for Ruby < 2.6
  klass_options.each do |k, v|
    options[k.to_sym] = v
  end

  jid = options.delete(:jid) || "123123"
  timecop_delay = options.delete(:timecop_delay)

  msg = Sidekiq.dump_json(created_at: Time.now.to_f, enqueued_at: Time.now.to_f, jid: jid, class: klass, args: [], **options)
  Timecop.freeze(timecop_delay) if timecop_delay
  work = Sidekiq::BasicFetch::UnitOfWork.new('queue:default', msg)
  process_work(processor, work)
ensure
  Timecop.return if timecop_delay
end

def process_work(processor, work)
  processor.send(:process, work)
rescue StandardError
  # do nothing
end

def perform_basic_setup
  Haystack.init do |config|
    config.dsn = DUMMY_DSN
    config.logger = ::Logger.new(nil)
    config.background_worker_threads = 0
    config.transport.transport_class = Haystack::DummyTransport
    yield config if block_given?
  end
end
