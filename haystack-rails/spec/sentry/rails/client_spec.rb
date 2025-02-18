# frozen_string_literal: true

require "spec_helper"

RSpec.describe Haystack::Client, type: :request, retry: 3, skip: Gem::Version.new(Rails.version) < Gem::Version.new('5.1.0') do
  let(:transport) do
    Haystack.get_current_client.transport
  end

  let(:expected_initial_active_record_connections_count) do
    if Gem::Version.new(Rails.version) < Gem::Version.new('7.2.0')
      1
    else
      0
    end
  end

  before do
    expect(ActiveRecord::Base.connection_pool.stat[:busy]).to eq(expected_initial_active_record_connections_count)
  end

  def send_events
    5.times.map do
      Thread.new { Haystack::Rails.capture_message("msg") }
    end.join
  end

  context "when serialization triggers ActiveRecord queries" do
    before do
      make_basic_app do |config|
        config.background_worker_threads = 5
        # simulate connection being obtained during event serialization
        # this could happen when serializing breadcrumbs
        config.before_send = lambda do |event, hint|
          Post.count
          event
        end
      end
    end

    it "doesn't hold the ActiveRecord connection after sending the event" do
      send_events

      sleep(0.5)

      expect(transport.events.count).to eq(5)

      expect(ActiveRecord::Base.connection_pool.stat[:busy]).to eq(expected_initial_active_record_connections_count)
    end
  end

  context "when serialization doesn't trigger ActiveRecord queries" do
    before do
      make_basic_app do |config|
        config.background_worker_threads = 5
      end
    end

    it "doesn't create any extra ActiveRecord connection when sending the event" do
      send_events

      sleep(0.1)

      expect(transport.events.count).to eq(5)

      expect(ActiveRecord::Base.connection_pool.stat[:busy]).to eq(expected_initial_active_record_connections_count)
    end
  end
end
