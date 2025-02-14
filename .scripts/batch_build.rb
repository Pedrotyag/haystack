INTEGRATIONS = %w(sentry-rails haystack-sidekiq sentry-delayed_job sentry-resque sentry-opentelemetry)
GEMS = %w(sentry-ruby) + INTEGRATIONS

success = GEMS.map do |gem_name|
  puts(`cd #{gem_name}; make build`)
  $?.success?
end.all?

exit success ? 0 : 1
