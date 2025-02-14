# frozen_string_literal: true

require "spec_helper"
require "haystack/rspec"

RSpec.describe "Haystack RSpec Matchers" do
  include Haystack::TestHelper

  before do
    # simulate normal user setup
    Haystack.init do |config|
      config.dsn = 'https://2fb45f003d054a7ea47feb45898f7649@o447951.ingest.haystack.io/5434472'
      config.enabled_environments = ["production"]
      config.environment = :test
    end

    setup_haystack_test
  end

  after do
    teardown_haystack_test
  end

  let(:exception) { StandardError.new("Gaah!") }

  describe "include_haystack_event" do
    it "matches events with the given message" do
      Haystack.capture_message("Ooops")

      expect(haystack_events).to include_haystack_event("Ooops")
    end

    it "does not match events with a different message" do
      Haystack.capture_message("Ooops")

      expect(haystack_events).not_to include_haystack_event("Different message")
    end

    it "matches events with exception" do
      Haystack.capture_exception(exception)

      expect(haystack_events).to include_haystack_event(exception: exception.class, message: exception.message)
    end

    it "does not match events with different exception" do
      exception = StandardError.new("Gaah!")

      Haystack.capture_exception(exception)

      expect(haystack_events).not_to include_haystack_event(exception: StandardError, message: "Oops!")
    end

    it "matches events with context" do
      Haystack.set_context("rails.error", { some: "stuff" })
      Haystack.capture_message("Ooops")

      expect(haystack_events).to include_haystack_event("Ooops")
        .with_context("rails.error" => { some: "stuff" })
    end

    it "does not match events with different context" do
      Haystack.set_context("rails.error", { some: "stuff" })
      Haystack.capture_message("Ooops")

      expect(haystack_events).not_to include_haystack_event("Ooops")
        .with_context("rails.error" => { other: "data" })
    end

    it "matches events with tags" do
      Haystack.set_tags(foo: "bar", baz: "qux")
      Haystack.capture_message("Ooops")

      expect(haystack_events).to include_haystack_event("Ooops")
        .with_tags({ foo: "bar", baz: "qux" })
    end

    it "does not match events with missing tags" do
      Haystack.set_tags(foo: "bar")
      Haystack.capture_message("Ooops")

      expect(haystack_events).not_to include_haystack_event("Ooops")
        .with_tags({ foo: "bar", baz: "qux" })
    end

    it "matches error events with tags and context" do
      Haystack.set_tags(foo: "bar", baz: "qux")
      Haystack.set_context("rails.error", { some: "stuff" })

      Haystack.capture_exception(exception)

      expect(haystack_events).to include_haystack_event(exception: exception.class, message: exception.message)
        .with_tags({ foo: "bar", baz: "qux" })
        .with_context("rails.error" => { some: "stuff" })
    end

    it "matches error events with tags and context provided as arguments" do
      Haystack.set_tags(foo: "bar", baz: "qux")
      Haystack.set_context("rails.error", { some: "stuff" })

      Haystack.capture_exception(exception)

      expect(haystack_events).to include_haystack_event(
        exception: exception.class,
        message: exception.message,
        tags: { foo: "bar", baz: "qux" },
        context: { "rails.error" => { some: "stuff" } }
      )
    end

    it "produces a useful failure message" do
      Haystack.capture_message("Actual message")

      expect {
        expect(haystack_events).to include_haystack_event("Expected message")
      }.to raise_error(RSpec::Expectations::ExpectationNotMetError) do |error|
        expect(error.message).to include("Failed to find event matching:")
        expect(error.message).to include("message: \"Expected message\"")
        expect(error.message).to include("Captured events:")
        expect(error.message).to include("\"message\": \"Actual message\"")
      end
    end
  end
end
