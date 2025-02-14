# frozen_string_literal: true

require "haystack/baggage"
require "haystack/profiler"
require "haystack/propagation_context"

module Haystack
  class Transaction < Span
    # @deprecated Use Haystack::PropagationContext::HAYSTACK_TRACE_REGEXP instead.
    HAYSTACK_TRACE_REGEXP = PropagationContext::HAYSTACK_TRACE_REGEXP

    UNLABELD_NAME = "<unlabeled transaction>"
    MESSAGE_PREFIX = "[Tracing]"

    # https://develop.haystack.dev/sdk/event-payloads/transaction/#transaction-annotations
    SOURCES = %i[custom url route view component task]

    include LoggingHelper

    # The name of the transaction.
    # @return [String]
    attr_reader :name

    # The source of the transaction name.
    # @return [Symbol]
    attr_reader :source

    # The sampling decision of the parent transaction, which will be considered when making the current transaction's sampling decision.
    # @return [String]
    attr_reader :parent_sampled

    # The parsed incoming W3C baggage header.
    # This is only for accessing the current baggage variable.
    # Please use the #get_baggage method for interfacing outside this class.
    # @return [Baggage, nil]
    attr_reader :baggage

    # The measurements added to the transaction.
    # @return [Hash]
    attr_reader :measurements

    # @deprecated Use Haystack.get_current_hub instead.
    attr_reader :hub

    # @deprecated Use Haystack.configuration instead.
    attr_reader :configuration

    # @deprecated Use Haystack.logger instead.
    attr_reader :logger

    # The effective sample rate at which this transaction was sampled.
    # @return [Float, nil]
    attr_reader :effective_sample_rate

    # Additional contexts stored directly on the transaction object.
    # @return [Hash]
    attr_reader :contexts

    # The Profiler instance for this transaction.
    # @return [Profiler]
    attr_reader :profiler

    def initialize(
      hub:,
      name: nil,
      source: :custom,
      parent_sampled: nil,
      baggage: nil,
      **options
    )
      super(transaction: self, **options)

      set_name(name, source: source)
      @parent_sampled = parent_sampled
      @hub = hub
      @baggage = baggage
      @configuration = hub.configuration # to be removed
      @tracing_enabled = hub.configuration.tracing_enabled?
      @traces_sampler = hub.configuration.traces_sampler
      @traces_sample_rate = hub.configuration.traces_sample_rate
      @logger = hub.configuration.logger
      @release = hub.configuration.release
      @environment = hub.configuration.environment
      @dsn = hub.configuration.dsn
      @effective_sample_rate = nil
      @contexts = {}
      @measurements = {}
      @profiler = @configuration.profiler_class.new(@configuration)
      init_span_recorder
    end

    # @deprecated use Haystack.continue_trace instead.
    #
    # Initalizes a Transaction instance with a Haystack trace string from another transaction (usually from an external request).
    #
    # The original transaction will become the parent of the new Transaction instance. And they will share the same `trace_id`.
    #
    # The child transaction will also store the parent's sampling decision in its `parent_sampled` attribute.
    # @param haystack_trace [String] the trace string from the previous transaction.
    # @param baggage [String, nil] the incoming baggage header string.
    # @param hub [Hub] the hub that'll be responsible for sending this transaction when it's finished.
    # @param options [Hash] the options you want to use to initialize a Transaction instance.
    # @return [Transaction, nil]
    def self.from_haystack_trace(haystack_trace, baggage: nil, hub: Haystack.get_current_hub, **options)
      return unless hub.configuration.tracing_enabled?
      return unless haystack_trace

      haystack_trace_data = extract_haystack_trace(haystack_trace)
      return unless haystack_trace_data

      trace_id, parent_span_id, parent_sampled = haystack_trace_data

      baggage =
        if baggage && !baggage.empty?
          Baggage.from_incoming_header(baggage)
        else
          # If there's an incoming haystack-trace but no incoming baggage header,
          # for instance in traces coming from older SDKs,
          # baggage will be empty and frozen and won't be populated as head SDK.
          Baggage.new({})
        end

      baggage.freeze!

      new(
        trace_id: trace_id,
        parent_span_id: parent_span_id,
        parent_sampled: parent_sampled,
        hub: hub,
        baggage: baggage,
        **options
      )
    end

    # @deprecated Use Haystack::PropagationContext.extract_haystack_trace instead.
    # @return [Array, nil]
    def self.extract_haystack_trace(haystack_trace)
      PropagationContext.extract_haystack_trace(haystack_trace)
    end

    # @return [Hash]
    def to_hash
      hash = super

      hash.merge!(
        name: @name,
        source: @source,
        sampled: @sampled,
        parent_sampled: @parent_sampled
      )

      hash
    end

    # @return [Transaction]
    def deep_dup
      copy = super
      copy.init_span_recorder(@span_recorder.max_length)

      @span_recorder.spans.each do |span|
        # span_recorder's first span is the current span, which should not be added to the copy's spans
        next if span == self
        copy.span_recorder.add(span.dup)
      end

      copy
    end

    # Sets a custom measurement on the transaction.
    # @param name [String] name of the measurement
    # @param value [Float] value of the measurement
    # @param unit [String] unit of the measurement
    # @return [void]
    def set_measurement(name, value, unit = "")
      @measurements[name] = { value: value, unit: unit }
    end

    # Sets initial sampling decision of the transaction.
    # @param sampling_context [Hash] a context Hash that'll be passed to `traces_sampler` (if provided).
    # @return [void]
    def set_initial_sample_decision(sampling_context:)
      unless @tracing_enabled
        @sampled = false
        return
      end

      unless @sampled.nil?
        @effective_sample_rate = @sampled ? 1.0 : 0.0
        return
      end

      sample_rate =
        if @traces_sampler.is_a?(Proc)
          @traces_sampler.call(sampling_context)
        elsif !sampling_context[:parent_sampled].nil?
          sampling_context[:parent_sampled]
        else
          @traces_sample_rate
        end

      transaction_description = generate_transaction_description

      if [true, false].include?(sample_rate)
        @effective_sample_rate = sample_rate ? 1.0 : 0.0
      elsif sample_rate.is_a?(Numeric) && sample_rate >= 0.0 && sample_rate <= 1.0
        @effective_sample_rate = sample_rate.to_f
      else
        @sampled = false
        log_warn("#{MESSAGE_PREFIX} Discarding #{transaction_description} because of invalid sample_rate: #{sample_rate}")
        return
      end

      if sample_rate == 0.0 || sample_rate == false
        @sampled = false
        log_debug("#{MESSAGE_PREFIX} Discarding #{transaction_description} because traces_sampler returned 0 or false")
        return
      end

      if sample_rate == true
        @sampled = true
      else
        if Haystack.backpressure_monitor
          factor = Haystack.backpressure_monitor.downsample_factor
          @effective_sample_rate /= 2**factor
        end

        @sampled = Random.rand < @effective_sample_rate
      end

      if @sampled
        log_debug("#{MESSAGE_PREFIX} Starting #{transaction_description}")
      else
        log_debug(
          "#{MESSAGE_PREFIX} Discarding #{transaction_description} because it's not included in the random sample (sampling rate = #{sample_rate})"
        )
      end
    end

    # Finishes the transaction's recording and send it to Haystack.
    # @param hub [Hub] the hub that'll send this transaction. (Deprecated)
    # @return [TransactionEvent]
    def finish(hub: nil, end_timestamp: nil)
      if hub
        log_warn(
          <<~MSG
            Specifying a different hub in `Transaction#finish` will be deprecated in version 5.0.
            Please use `Hub#start_transaction` with the designated hub.
          MSG
        )
      end

      hub ||= @hub

      super(end_timestamp: end_timestamp)

      if @name.nil?
        @name = UNLABELD_NAME
      end

      @profiler.stop

      if @sampled
        event = hub.current_client.event_from_transaction(self)
        hub.capture_event(event)
      else
        is_backpressure = Haystack.backpressure_monitor&.downsample_factor&.positive?
        reason = is_backpressure ? :backpressure : :sample_rate
        hub.current_client.transport.record_lost_event(reason, "transaction")
        hub.current_client.transport.record_lost_event(reason, "span")
      end
    end

    # Get the existing frozen incoming baggage
    # or populate one with haystack- items as the head SDK.
    # @return [Baggage]
    def get_baggage
      populate_head_baggage if @baggage.nil? || @baggage.mutable
      @baggage
    end

    # Set the transaction name directly.
    # Considered internal api since it bypasses the usual scope logic.
    # @param name [String]
    # @param source [Symbol]
    # @return [void]
    def set_name(name, source: :custom)
      @name = name
      @source = SOURCES.include?(source) ? source.to_sym : :custom
    end

    # Set contexts directly on the transaction.
    # @param key [String, Symbol]
    # @param value [Object]
    # @return [void]
    def set_context(key, value)
      @contexts[key] = value
    end

    # Start the profiler.
    # @return [void]
    def start_profiler!
      profiler.set_initial_sample_decision(sampled)
      profiler.start
    end

    # These are high cardinality and thus bad
    def source_low_quality?
      source == :url
    end

    protected

    def init_span_recorder(limit = 1000)
      @span_recorder = SpanRecorder.new(limit)
      @span_recorder.add(self)
    end

    private

    def generate_transaction_description
      result = op.nil? ? "" : "<#{@op}> "
      result += "transaction"
      result += " <#{@name}>" if @name
      result
    end

    def populate_head_baggage
      items = {
        "trace_id" => trace_id,
        "sample_rate" => effective_sample_rate&.to_s,
        "sampled" => sampled&.to_s,
        "environment" => @environment,
        "release" => @release,
        "public_key" => @dsn&.public_key
      }

      items["transaction"] = name unless source_low_quality?

      user = @hub.current_scope&.user
      items["user_segment"] = user["segment"] if user && user["segment"]

      items.compact!
      @baggage = Baggage.new(items, mutable: false)
    end

    class SpanRecorder
      attr_reader :max_length, :spans

      def initialize(max_length)
        @max_length = max_length
        @spans = []
      end

      def add(span)
        if @spans.count < @max_length
          @spans << span
        end
      end
    end
  end
end
