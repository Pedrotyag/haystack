# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Haystack::Breadcrumbs::HaystackLogger" do
  before do
    perform_basic_setup do |config|
      config.breadcrumbs_logger = [:haystack_logger]
    end
  end

  let(:logger) { ::Logger.new(nil) }
  let(:breadcrumbs) { Haystack.get_current_scope.breadcrumbs }

  it "records the breadcrumb when logger is called" do
    logger.info("foo")

    breadcrumb = breadcrumbs.peek

    expect(breadcrumb.level).to eq("info")
    expect(breadcrumb.message).to eq("foo")
  end

  it "records non-String message" do
    logger.info(200)
    expect(breadcrumbs.peek.message).to eq("200")
  end

  it "does not affect the return of the logger call" do
    expect(logger.info("foo")).to be_nil
  end

  it "ignores traces with #{Haystack::LOGGER_PROGNAME}" do
    logger.info(Haystack::LOGGER_PROGNAME) { "foo" }

    expect(breadcrumbs.peek).to be_nil
  end

  it "passes severity as a hint" do
    hint = nil
    Haystack.configuration.before_breadcrumb = lambda do |breadcrumb, h|
      hint = h
      breadcrumb
    end

    logger.info("foo")

    expect(breadcrumbs.peek.message).to eq("foo")
    expect(hint[:severity]).to eq(1)
  end

  describe "category assignment" do
    it "assigned 'logger' by default" do
      logger.info("foo")

      expect(breadcrumbs.peek.category).to eq("logger")
    end

    it "assigns progname if provided" do
      logger.info("test category") { "foo" }

      expect(breadcrumbs.peek.category).to eq("test category")
    end
  end

  describe "when closed" do
    it "noops" do
      Haystack.close
      expect(Haystack).not_to receive(:add_breadcrumb)
      logger.info("foo")
    end

    # see https://github.com/gethaystack/haystack/issues/1858
    unless RUBY_PLATFORM == "java"
      it "noops on thread with cloned hub" do
        mutex = Mutex.new
        cv = ConditionVariable.new

        a = Thread.new do
          expect(Haystack.get_current_hub).to be_a(Haystack::Hub)

          # close in another thread
          b = Thread.new do
            mutex.synchronize do
              Haystack.close
              cv.signal
            end
          end

          mutex.synchronize do
            # wait for other thread to close SDK
            cv.wait(mutex)

            expect(Haystack).not_to receive(:add_breadcrumb)
            logger.info("foo")
          end

          b.join
        end

        a.join
      end
    end
  end
end
