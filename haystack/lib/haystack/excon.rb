# frozen_string_literal: true

Haystack.register_patch(:excon) do
  if defined?(::Excon)
    require "haystack/excon/middleware"
    if Excon.defaults[:middlewares]
      Excon.defaults[:middlewares] << Haystack::Excon::Middleware unless Excon.defaults[:middlewares].include?(Haystack::Excon::Middleware)
    end
  end
end
