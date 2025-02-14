# frozen_string_literal: true

require 'spec_helper'
require 'haystack/interface'

class TestInterface < Haystack::Interface
  attr_accessor :some_attr
end

RSpec.describe Haystack::Interface do
  it "serializes to a Hash" do
    interface = TestInterface.new
    interface.some_attr = "test"

    expect(interface.to_hash).to eq(some_attr: "test")
  end
end
