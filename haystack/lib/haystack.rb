# frozen_string_literal: true

require "English"
require "forwardable"
require "time"

require "haystack/version"
require "haystack/exceptions"
require "haystack/core_ext/object/deep_dup"
require "haystack/utils/argument_checking_helper"
require "haystack/utils/encoding_helper"
require "haystack/utils/logging_helper"
require "haystack/configuration"
require "haystack/logger"
require "haystack/event"
require "haystack/error_event"
require "haystack/transaction_event"
require "haystack/check_in_event"
require "haystack/span"
require "haystack/transaction"
require "haystack/hub"
require "haystack/background_worker"
require "haystack/threaded_periodic_worker"
require "haystack/session_flusher"
require "haystack/backpressure_monitor"
require "haystack/cron/monitor_check_ins"
require "haystack/metrics"
require "haystack/vernier/profiler"

[
  "haystack/rake",
  "haystack/rack"
].each do |lib|
  begin
    require lib
  rescue LoadError
  end
end

module Haystack
  META = { "name" => "haystack.ruby", "version" => Haystack::VERSION }.freeze

  CAPTURED_SIGNATURE = :@__haystack_captured

  LOGGER_PROGNAME = "haystack"

  HAYSTACK_TRACE_HEADER_NAME = "haystack-trace"

  BAGGAGE_HEADER_NAME = "baggage"

  THREAD_LOCAL = :haystack_hub

  MUTEX = Mutex.new

  class << self
    # @!visibility private
    def exception_locals_tp
      @exception_locals_tp ||= TracePoint.new(:raise) do |tp|
        exception = tp.raised_exception

        # don't collect locals again if the exception is re-raised
        next if exception.instance_variable_get(:@haystack_locals)
        next unless tp.binding

        locals = tp.binding.local_variables.each_with_object({}) do |local, result|
          result[local] = tp.binding.local_variable_get(local)
        end

        exception.instance_variable_set(:@haystack_locals, locals)
      end
    end

    # @!attribute [rw] background_worker
    #   @return [BackgroundWorker]
    attr_accessor :background_worker

    # @!attribute [r] session_flusher
    #   @return [SessionFlusher, nil]
    attr_reader :session_flusher

    # @!attribute [r] backpressure_monitor
    #   @return [BackpressureMonitor, nil]
    attr_reader :backpressure_monitor

    # @!attribute [r] metrics_aggregator
    #   @return [Metrics::Aggregator, nil]
    attr_reader :metrics_aggregator

    ##### Patch Registration #####

    # @!visibility private
    def register_patch(key, patch = nil, target = nil, &block)
      if patch && block
        raise ArgumentError.new("Please provide either a patch and its target OR a block, but not both")
      end

      if block
        registered_patches[key] = block
      else
        registered_patches[key] = proc do
          target.send(:prepend, patch) unless target.ancestors.include?(patch)
        end
      end
    end

    # @!visibility private
    def apply_patches(config)
      registered_patches.each do |key, patch|
        patch.call(config) if config.enabled_patches.include?(key)
      end
    end

    # @!visibility private
    def registered_patches
      @registered_patches ||= {}
    end

    ##### Integrations #####

    # Returns a hash that contains all the integrations that have been registered to the main SDK.
    #
    # @return [Hash{String=>Hash}]
    def integrations
      @integrations ||= {}
    end

    # Registers the SDK integration with its name and version.
    #
    # @param name [String] name of the integration
    # @param version [String] version of the integration
    def register_integration(name, version)
      if initialized?
        logger.warn(LOGGER_PROGNAME) do
          <<~MSG
            Integration '#{name}' is loaded after the SDK is initialized, which can cause unexpected behavior.  Please make sure all integrations are loaded before SDK initialization.
          MSG
        end
      end

      meta = { name: "haystack.ruby.#{name}", version: version }.freeze
      integrations[name.to_s] = meta
    end

    ##### Method Delegation #####

    extend Forwardable

    # @!macro [new] configuration
    #   The Configuration object that's used for configuring the client and its transport.
    #   @return [Configuration]
    # @!macro [new] send_event
    #   Sends the event to Haystack.
    #   @param event [Event] the event to be sent.
    #   @param hint [Hash] the hint data that'll be passed to `before_send` callback.
    #   @return [Event]

    # @!method configuration
    #   @!macro configuration
    def configuration
      return unless initialized?
      get_current_client.configuration
    end

    # @!method send_event
    #   @!macro send_event
    def send_event(*args)
      return unless initialized?
      get_current_client.send_event(*args)
    end

    # @!macro [new] set_extras
    #   Updates the scope's extras attribute by merging with the old value.
    #   @param extras [Hash]
    #   @return [Hash]
    # @!macro [new] set_user
    #   Sets the scope's user attribute.
    #   @param user [Hash]
    #   @return [Hash]
    # @!macro [new] set_context
    #   Adds a new key-value pair to current contexts.
    #   @param key [String, Symbol]
    #   @param value [Object]
    #   @return [Hash]
    # @!macro [new] set_tags
    #   Updates the scope's tags attribute by merging with the old value.
    #   @param tags [Hash]
    #   @return [Hash]

    # @!method set_tags
    #   @!macro set_tags
    def set_tags(*args)
      return unless initialized?
      get_current_scope.set_tags(*args)
    end

    # @!method set_extras
    #   @!macro set_extras
    def set_extras(*args)
      return unless initialized?
      get_current_scope.set_extras(*args)
    end

    # @!method set_user
    #   @!macro set_user
    def set_user(*args)
      return unless initialized?
      get_current_scope.set_user(*args)
    end

    # @!method set_context
    #   @!macro set_context
    def set_context(*args)
      return unless initialized?
      get_current_scope.set_context(*args)
    end

    # @!method add_attachment
    #   @!macro add_attachment
    def add_attachment(**opts)
      return unless initialized?
      get_current_scope.add_attachment(**opts)
    end

    ##### Main APIs #####

    # Initializes the SDK with given configuration.
    #
    # @yieldparam config [Configuration]
    # @return [void]
    def init(&block)
      config = Configuration.new
      yield(config) if block_given?
      config.detect_release
      apply_patches(config)
      client = Client.new(config)
      scope = Scope.new(max_breadcrumbs: config.max_breadcrumbs)
      hub = Hub.new(client, scope)
      Thread.current.thread_variable_set(THREAD_LOCAL, hub)
      @main_hub = hub
      @global_configuration = config
      @background_worker = Haystack::BackgroundWorker.new(config)
      @session_flusher = config.session_tracking? ? Haystack::SessionFlusher.new(config, client) : nil
      @backpressure_monitor = config.enable_backpressure_handling ? Haystack::BackpressureMonitor.new(config, client) : nil
      @metrics_aggregator = config.metrics.enabled ? Haystack::Metrics::Aggregator.new(config, client) : nil
      exception_locals_tp.enable if config.include_local_variables
      at_exit { close }
    end

    # Flushes pending events and cleans up SDK state.
    # SDK will stop sending events and all top-level APIs will be no-ops after this.
    #
    # @return [void]
    def close
      if @session_flusher
        @session_flusher.flush
        @session_flusher.kill
        @session_flusher = nil
      end

      if @backpressure_monitor
        @backpressure_monitor.kill
        @backpressure_monitor = nil
      end

      if @metrics_aggregator
        @metrics_aggregator.flush(force: true)
        @metrics_aggregator.kill
        @metrics_aggregator = nil
      end

      if client = get_current_client
        client.flush

        if client.configuration.include_local_variables
          exception_locals_tp.disable
        end
      end

      @background_worker.shutdown

      MUTEX.synchronize do
        @main_hub = nil
        Thread.current.thread_variable_set(THREAD_LOCAL, nil)
      end
    end

    # Returns true if the SDK is initialized.
    #
    # @return [Boolean]
    def initialized?
      !!get_main_hub
    end

    # Returns an uri for security policy reporting that's generated from the given DSN
    # (To learn more about security policy reporting: https://docs.haystack.io/product/security-policy-reporting/)
    #
    # It returns nil if
    # - The SDK is not initialized yet.
    # - The DSN is not provided or is invalid.
    #
    # @return [String, nil]
    def csp_report_uri
      return unless initialized?
      configuration.csp_report_uri
    end

    # Returns the main thread's active hub.
    #
    # @return [Hub]
    def get_main_hub
      MUTEX.synchronize { @main_hub }
    end

    # Takes an instance of Haystack::Breadcrumb and stores it to the current active scope.
    #
    # @return [Breadcrumb, nil]
    def add_breadcrumb(breadcrumb, **options)
      return unless initialized?
      get_current_hub.add_breadcrumb(breadcrumb, **options)
    end

    # Returns the current active hub.
    # If the current thread doesn't have an active hub, it will clone the main thread's active hub,
    # stores it in the current thread, and then returns it.
    #
    # @return [Hub]
    def get_current_hub
      # we need to assign a hub to the current thread if it doesn't have one yet
      #
      # ideally, we should do this proactively whenever a new thread is created
      # but it's impossible for the SDK to keep track every new thread
      # so we need to use this rather passive way to make sure the app doesn't crash
      Thread.current.thread_variable_get(THREAD_LOCAL) || clone_hub_to_current_thread
    end

    # Returns the current active client.
    # @return [Client, nil]
    def get_current_client
      return unless initialized?
      get_current_hub.current_client
    end

    # Returns the current active scope.
    #
    # @return [Scope, nil]
    def get_current_scope
      return unless initialized?
      get_current_hub.current_scope
    end

    # Clones the main thread's active hub and stores it to the current thread.
    #
    # @return [void]
    def clone_hub_to_current_thread
      return unless initialized?
      Thread.current.thread_variable_set(THREAD_LOCAL, get_main_hub.clone)
    end

    # Takes a block and yields the current active scope.
    #
    # @example
    #   Haystack.configure_scope do |scope|
    #     scope.set_tags(foo: "bar")
    #   end
    #
    #   Haystack.capture_message("test message") # this event will have tags { foo: "bar" }
    #
    # @yieldparam scope [Scope]
    # @return [void]
    def configure_scope(&block)
      return unless initialized?
      get_current_hub.configure_scope(&block)
    end

    # Takes a block and yields a temporary scope.
    # The temporary scope will inherit all the attributes from the current active scope and replace it to be the active
    # scope inside the block.
    #
    # @example
    #   Haystack.configure_scope do |scope|
    #     scope.set_tags(foo: "bar")
    #   end
    #
    #   Haystack.capture_message("test message") # this event will have tags { foo: "bar" }
    #
    #   Haystack.with_scope do |temp_scope|
    #     temp_scope.set_tags(foo: "baz")
    #     Haystack.capture_message("test message 2") # this event will have tags { foo: "baz" }
    #   end
    #
    #   Haystack.capture_message("test message 3") # this event will have tags { foo: "bar" }
    #
    # @yieldparam scope [Scope]
    # @return [void]
    def with_scope(&block)
      return yield unless initialized?
      get_current_hub.with_scope(&block)
    end

    # Wrap a given block with session tracking.
    # Aggregate sessions in minutely buckets will be recorded
    # around this block and flushed every minute.
    #
    # @example
    #   Haystack.with_session_tracking do
    #     a = 1 + 1 # new session recorded with :exited status
    #   end
    #
    #   Haystack.with_session_tracking do
    #     1 / 0
    #   rescue => e
    #     Haystack.capture_exception(e) # new session recorded with :errored status
    #   end
    # @return [void]
    def with_session_tracking(&block)
      return yield unless initialized?
      get_current_hub.with_session_tracking(&block)
    end

    # Takes an exception and reports it to Haystack via the currently active hub.
    #
    # @yieldparam scope [Scope]
    # @return [Event, nil]
    def capture_exception(exception, **options, &block)
      return unless initialized?
      get_current_hub.capture_exception(exception, **options, &block)
    end

    # Takes a block and evaluates it. If the block raised an exception, it reports the exception to Haystack and re-raises it.
    # If the block ran without exception, it returns the evaluation result.
    #
    # @example
    #   Haystack.with_exception_captured do
    #     1/1 #=> 1 will be returned
    #   end
    #
    #   Haystack.with_exception_captured do
    #     1/0 #=> ZeroDivisionError will be reported and re-raised
    #   end
    #
    def with_exception_captured(**options, &block)
      yield
    rescue Exception => e
      capture_exception(e, **options)
      raise
    end

    # Takes a message string and reports it to Haystack via the currently active hub.
    #
    # @yieldparam scope [Scope]
    # @return [Event, nil]
    def capture_message(message, **options, &block)
      return unless initialized?
      get_current_hub.capture_message(message, **options, &block)
    end

    # Takes an instance of Haystack::Event and dispatches it to the currently active hub.
    #
    # @return [Event, nil]
    def capture_event(event)
      return unless initialized?
      get_current_hub.capture_event(event)
    end

    # Captures a check-in and sends it to Haystack via the currently active hub.
    #
    # @param slug [String] identifier of this monitor
    # @param status [Symbol] status of this check-in, one of {CheckInEvent::VALID_STATUSES}
    #
    # @param [Hash] options extra check-in options
    # @option options [String] check_in_id for updating the status of an existing monitor
    # @option options [Integer] duration seconds elapsed since this monitor started
    # @option options [Cron::MonitorConfig] monitor_config configuration for this monitor
    #
    # @return [String, nil] The {CheckInEvent#check_in_id} to use for later updates on the same slug
    def capture_check_in(slug, status, **options)
      return unless initialized?
      get_current_hub.capture_check_in(slug, status, **options)
    end

    # Takes or initializes a new Haystack::Transaction and makes a sampling decision for it.
    #
    # @return [Transaction, nil]
    def start_transaction(**options)
      return unless initialized?
      get_current_hub.start_transaction(**options)
    end

    # Records the block's execution as a child of the current span.
    # If the current scope doesn't have a span, the block would still be executed but the yield param will be nil.
    # @param attributes [Hash] attributes for the child span.
    # @yieldparam child_span [Span, nil]
    # @return yield result
    #
    # @example
    #   Haystack.with_child_span(op: "my operation") do |child_span|
    #     child_span.set_data(operation_data)
    #     child_span.set_description(operation_detail)
    #     # result will be returned
    #   end
    #
    def with_child_span(**attributes, &block)
      return yield(nil) unless Haystack.initialized?
      get_current_hub.with_child_span(**attributes, &block)
    end

    # Returns the id of the lastly reported Haystack::Event.
    #
    # @return [String, nil]
    def last_event_id
      return unless initialized?
      get_current_hub.last_event_id
    end

    # Checks if the exception object has been captured by the SDK.
    #
    # @return [Boolean]
    def exception_captured?(exc)
      return false unless initialized?
      !!exc.instance_variable_get(CAPTURED_SIGNATURE)
    end

    # Add a global event processor [Proc].
    # These run before scope event processors.
    #
    # @yieldparam event [Event]
    # @yieldparam hint [Hash, nil]
    # @return [void]
    #
    # @example
    #   Haystack.add_global_event_processor do |event, hint|
    #     event.tags = { foo: 42 }
    #     event
    #   end
    #
    def add_global_event_processor(&block)
      Scope.add_global_event_processor(&block)
    end

    # Returns the traceparent (haystack-trace) header for distributed tracing.
    # Can be either from the currently active span or the propagation context.
    #
    # @return [String, nil]
    def get_traceparent
      return nil unless initialized?
      get_current_hub.get_traceparent
    end

    # Returns the baggage header for distributed tracing.
    # Can be either from the currently active span or the propagation context.
    #
    # @return [String, nil]
    def get_baggage
      return nil unless initialized?
      get_current_hub.get_baggage
    end

    # Returns the a Hash containing haystack-trace and baggage.
    # Can be either from the currently active span or the propagation context.
    #
    # @return [Hash, nil]
    def get_trace_propagation_headers
      return nil unless initialized?
      get_current_hub.get_trace_propagation_headers
    end

    # Returns the a Hash containing haystack-trace and baggage.
    # Can be either from the currently active span or the propagation context.
    #
    # @return [String]
    def get_trace_propagation_meta
      return "" unless initialized?
      get_current_hub.get_trace_propagation_meta
    end

    # Continue an incoming trace from a rack env like hash.
    #
    # @param env [Hash]
    # @return [Transaction, nil]
    def continue_trace(env, **options)
      return nil unless initialized?
      get_current_hub.continue_trace(env, **options)
    end

    ##### Helpers #####

    # @!visibility private
    def sys_command(command)
      result = `#{command} 2>&1` rescue nil
      return if result.nil? || result.empty? || ($CHILD_STATUS && $CHILD_STATUS.exitstatus != 0)

      result.strip
    end

    # @!visibility private
    def logger
      configuration.logger
    end

    # @!visibility private
    def sdk_meta
      META
    end

    # @!visibility private
    def utc_now
      Time.now.utc
    end
  end
end

# patches
require "haystack/net/http"
require "haystack/redis"
require "haystack/puma"
require "haystack/graphql"
require "haystack/faraday"
require "haystack/excon"
