# frozen_string_literal: true

module Haystack
  class Transport
    class Configuration
      # The timeout in seconds to open a connection to Haystack, in seconds.
      # Default value is 2.
      #
      # @return [Integer]
      attr_accessor :timeout

      # The timeout in seconds to read data from Haystack, in seconds.
      # Default value is 1.
      #
      # @return [Integer]
      attr_accessor :open_timeout

      # The proxy configuration to use to connect to Haystack.
      # Accepts either a URI formatted string, URI, or a hash with the `uri`,
      # `user`, and `password` keys.
      #
      # @example
      #   # setup proxy using a string:
      #   config.transport.proxy = "https://user:password@proxyhost:8080"
      #
      #   # setup proxy using a URI:
      #   config.transport.proxy = URI("https://user:password@proxyhost:8080")
      #
      #   # setup proxy using a hash:
      #   config.transport.proxy = {
      #     uri: URI("https://proxyhost:8080"),
      #     user: "user",
      #     password: "password"
      #   }
      #
      # If you're using the default transport (`Haystack::HTTPTransport`),
      # proxy settings will also automatically be read from tne environment
      # variables (`HTTP_PROXY`, `HTTPS_PROXY`, `NO_PROXY`).
      #
      # @return [String, URI, Hash, nil]
      attr_accessor :proxy

      # The SSL configuration to use to connect to Haystack.
      # You can either pass a `Hash` containing `ca_file` and `verification` keys,
      # or you can set those options directly on the `Haystack::HTTPTransport::Configuration` object:
      #
      # @example
      #   config.transport.ssl =  {
      #     ca_file: "/path/to/ca_file",
      #     verification: true
      #   end
      #
      # @return [Hash, nil]
      attr_accessor :ssl

      # The path to the CA file to use to verify the SSL connection.
      # Default value is `nil`.
      #
      # @return [String, nil]
      attr_accessor :ssl_ca_file

      # Whether to verify that the peer certificate is valid in SSL connections.
      # Default value is `true`.
      #
      # @return [Boolean]
      attr_accessor :ssl_verification

      # The encoding to use to compress the request body.
      # Default value is `Haystack::HTTPTransport::GZIP_ENCODING`.
      #
      # @return [String]
      attr_accessor :encoding

      # The class to use as a transport to connect to Haystack.
      # If this option not set, it will return `nil`, and Haystack will use
      # `Haystack::HTTPTransport` by default.
      #
      # @return [Class, nil]
      attr_reader :transport_class

      def initialize
        @ssl_verification = true
        @open_timeout = 1
        @timeout = 2
        @encoding = HTTPTransport::GZIP_ENCODING
      end

      def transport_class=(klass)
        unless klass.is_a?(Class)
          raise Haystack::Error.new("config.transport.transport_class must a class. got: #{klass.class}")
        end

        @transport_class = klass
      end
    end
  end
end
