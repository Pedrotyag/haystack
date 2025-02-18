# frozen_string_literal: true

require "spec_helper"

RSpec.describe Haystack::Breadcrumb do
  before do
    perform_basic_setup
  end

  let(:crumb) do
    Haystack::Breadcrumb.new(
      category: "foo",
      message: "crumb",
      data: {
        name: "John",
        age: 25
      }
    )
  end

  describe "#initialize" do
    it "limits the maximum size of message" do
      long_message = "a" * Haystack::Event::MAX_MESSAGE_SIZE_IN_BYTES * 2

      crumb = described_class.new(message: long_message)
      expect(crumb.message.length).to eq(Haystack::Event::MAX_MESSAGE_SIZE_IN_BYTES + 1)
    end

    it "sets the level to warning if warn" do
      crumb = described_class.new(level: "warn")
      expect(crumb.level).to eq("warning")
    end
  end

  describe "#message=" do
    it "limits the maximum size of message" do
      long_message = "a" * Haystack::Event::MAX_MESSAGE_SIZE_IN_BYTES * 2

      crumb = described_class.new
      crumb.message = long_message
      expect(crumb.message.length).to eq(Haystack::Event::MAX_MESSAGE_SIZE_IN_BYTES + 1)
    end
  end

  describe "#level=" do
    it "sets the level" do
      crumb = described_class.new
      crumb.level = "error"
      expect(crumb.level).to eq("error")
    end

    it "sets the level to warning if warn" do
      crumb = described_class.new
      crumb.level = "warn"
      expect(crumb.level).to eq("warning")
    end
  end

  describe "#to_hash" do
    let(:problematic_crumb) do
      # circular reference
      a = []
      b = []
      a.push(b)
      b.push(a)

      Haystack::Breadcrumb.new(
        category: "baz",
        message: "I cause issues",
        data: a
      )
    end

    it "serializes data correctly" do
      result = crumb.to_hash

      expect(result[:category]).to eq("foo")
      expect(result[:message]).to eq("crumb")
      expect(result[:data]).to eq({ "name" => "John", "age" => 25 })
    end

    it "rescues data serialization issue and ditch the data" do
      result = problematic_crumb.to_hash

      expect(result[:category]).to eq("baz")
      expect(result[:message]).to eq("I cause issues")
      expect(result[:data]).to eq("[data were removed due to serialization issues]")
    end
  end
end
