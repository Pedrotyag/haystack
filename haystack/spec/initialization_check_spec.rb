# frozen_string_literal: true

require "spec_helper"

RSpec.describe "with uninitialized SDK" do
  before do
    # completely nuke any initialized hubs
    Haystack.instance_variable_set(:@main_hub, nil)
    expect(Haystack.initialized?).to eq(false)
  end

  it { expect(Haystack.configuration).to eq(nil) }
  it { expect(Haystack.send_event(nil)).to eq(nil) }
  it { expect(Haystack.capture_exception(Exception.new)).to eq(nil) }
  it { expect(Haystack.capture_message("foo")).to eq(nil) }
  it { expect(Haystack.capture_event(nil)).to eq(nil) }
  it { expect(Haystack.set_tags(foo: "bar")).to eq(nil) }
  it { expect(Haystack.set_user(name: "John")).to eq(nil) }
  it { expect(Haystack.set_extras(foo: "bar")).to eq(nil) }
  it { expect(Haystack.set_context(foo:  { bar: "baz" })).to eq(nil) }
  it { expect(Haystack.last_event_id).to eq(nil) }
  it { expect(Haystack.exception_captured?(Exception.new)).to eq(false) }
  it do
    expect { Haystack.configure_scope { raise "foo" } }.not_to raise_error(RuntimeError)
  end

  it do
    expect { Haystack.with_exception_captured { raise "foo" } }.to raise_error(RuntimeError)
  end

  it do
    result = Haystack.with_child_span { |span| "foo" }
    expect(result).to eq("foo")
  end

  it do
    result = Haystack.with_scope { |scope| "foo" }
    expect(result).to eq("foo")
  end

  it do
    result = Haystack.with_session_tracking { |scope| "foo" }
    expect(result).to eq("foo")
  end
end
