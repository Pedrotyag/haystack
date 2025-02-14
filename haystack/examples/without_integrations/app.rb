require "haystack"

Haystack.init do |config|
  config.dsn = 'https://2fb45f003d054a7ea47feb45898f7649@o447951.ingest.haystack.io/5434472'
end

Haystack.capture_message("test Haystack", hint: { background: false })
