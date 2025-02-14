# frozen_string_literal: true

Haystack.register_patch(:graphql) do |config|
  if defined?(::GraphQL::Schema) && defined?(::GraphQL::Tracing::HaystackTrace) && ::GraphQL::Schema.respond_to?(:trace_with)
    ::GraphQL::Schema.trace_with(::GraphQL::Tracing::HaystackTrace, set_transaction_name: true)
  else
    config.logger.warn(Haystack::LOGGER_PROGNAME) { "You tried to enable the GraphQL integration but no GraphQL gem was detected. Make sure you have the `graphql` gem (>= 2.2.6) in your Gemfile." }
  end
end
