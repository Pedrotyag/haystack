# frozen_string_literal: true

require "spec_helper"

RSpec.describe Haystack::TestHelper do
  include described_class

  before do
    # simulate normal user setup
    Haystack.init do |config|
      config.dsn = 'https://2fb45f003d054a7ea47feb45898f7649@o447951.ingest.haystack.io/5434472'
      config.enabled_environments = ["production"]
      config.environment = :test
    end

    expect(Haystack.configuration.dsn.to_s).to eq('https://2fb45f003d054a7ea47feb45898f7649@o447951.ingest.haystack.io/5434472')
    expect(Haystack.configuration.enabled_environments).to eq(["production"])
    expect(Haystack.get_current_client.transport).to be_a(Haystack::HTTPTransport)
  end

  describe "#setup_haystack_test" do
    after do
      teardown_haystack_test
    end

    it "raises error when the SDK is not initialized" do
      allow(Haystack).to receive(:initialized?).and_return(false)

      expect do
        setup_haystack_test
      end.to raise_error(RuntimeError)
    end

    it "overrides DSN, enabled_environments and transport for testing" do
      setup_haystack_test

      expect(Haystack.configuration.dsn.to_s).to eq(Haystack::TestHelper::DUMMY_DSN)
      expect(Haystack.configuration.enabled_environments).to eq(["production", "test"])
      expect(Haystack.get_current_client.transport).to be_a(Haystack::DummyTransport)
    end

    it "takes block argument for further customization" do
      setup_haystack_test do |config|
        config.traces_sample_rate = 1.0
      end

      expect(Haystack.configuration.traces_sample_rate).to eq(1.0)
    end
  end

  describe "#last_haystack_event" do
    before do
      setup_haystack_test
    end

    after do
      teardown_haystack_test
    end

    it "returns the last sent event" do
      Haystack.capture_message("foobar")
      Haystack.capture_message("barbaz")

      event = last_haystack_event

      expect(event.message).to eq("barbaz")
    end
  end

  describe "#extract_haystack_exceptions" do
    before do
      setup_haystack_test
    end

    after do
      teardown_haystack_test
    end

    it "extracts exceptions from an ErrorEvent" do
      event = Haystack.get_current_client.event_from_exception(Exception.new("foobar"))

      exceptions = extract_haystack_exceptions(event)

      expect(exceptions.count).to eq(1)
      expect(exceptions.first.type).to eq("Exception")
    end

    it "returns an empty array when there's no exceptions" do
      event = Haystack.get_current_client.event_from_message("foo")

      exceptions = extract_haystack_exceptions(event)

      expect(exceptions.count).to eq(0)
    end
  end

  describe "#teardown_haystack_test" do
    before do
      setup_haystack_test
    end

    it "clears stored events" do
      Haystack.capture_message("foobar")

      expect(haystack_events.count).to eq(1)

      teardown_haystack_test

      expect(haystack_events.count).to eq(0)
    end

    it "clears stored envelopes" do
      event = Haystack.get_current_client.event_from_message("foobar")
      envelope = haystack_transport.envelope_from_event(event)
      haystack_transport.send_envelope(envelope)

      expect(haystack_envelopes.count).to eq(1)

      teardown_haystack_test

      expect(haystack_envelopes.count).to eq(0)
    end

    it "clears the scope" do
      Haystack.set_tags(foo: "bar")

      teardown_haystack_test

      expect(Haystack.get_current_scope.tags).to eq({})
    end

    it "clears global processors" do
      Haystack.add_global_event_processor { |event| event }
      teardown_haystack_test
      expect(Haystack::Scope.global_event_processors).to eq([])
    end

    context "when the configuration is mutated" do
      it "rolls back client changes" do
        Haystack.configuration.environment = "quack"
        expect(Haystack.configuration.environment).to eq("quack")

        teardown_haystack_test

        expect(Haystack.configuration.environment).to eq("test")
      end
    end
  end
end
