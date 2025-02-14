# frozen_string_literal: true

require "sidekiq"
require "haystack-sidekiq"

Haystack.init do |config|
  config.breadcrumbs_logger = [:haystack_logger]
  # replace it with your haystack dsn
  config.dsn = 'https://2fb45f003d054a7ea47feb45898f7649@o447951.ingest.haystack.io/5434472'
end

class ErrorWorker
  include Sidekiq::Worker

  sidekiq_options retry: 0

  def perform
    1 / 0
  end
end

ErrorWorker.perform_async
