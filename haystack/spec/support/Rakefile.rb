# frozen_string_literal: true

require "rake"
require "haystack"

Haystack.init do |config|
  config.dsn = 'http://12345:67890@haystack.localdomain/haystack/42'
  config.background_worker_threads = 0
  config.logger.level = Logger::DEBUG
end

task :raise_exception do
  1/0
end

task :raise_exception_without_rake_integration do
  Haystack.configuration.skip_rake_integration = true
  1/0
end

task :pass_arguments, ['name']  do |_task, args|
  puts args[:name]
end
