# frozen_string_literal: true

require "spec_helper"

RSpec.describe Haystack::Transport::Configuration do
  describe "#transport_class=" do
    it "doesn't accept non-class argument" do
      expect { subject.transport_class = "foo" }.to raise_error(Haystack::Error, "config.transport.transport_class must a class. got: String")
    end

    it "accepts class argument" do
      subject.transport_class = Haystack::DummyTransport

      expect(subject.transport_class).to eq(Haystack::DummyTransport)
    end
  end
end
