require 'json'
require 'base64'
require 'concurrent'

require 'opentracing'

require 'lightstep/span'
require 'lightstep/reporter'
require 'lightstep/transport/http_json'
require 'lightstep/transport/nil'
require 'lightstep/transport/callback'

module LightStep
  class Tracer
    class Error < LightStep::Error; end
    class ConfigurationError < LightStep::Tracer::Error; end

    attr_reader :access_token, :guid

    # Initialize a new tracer. Either an access_token or a transport must be
    # provided. A component_name is always required.
    # @param component_name [String] Component name to use for the tracer
    # @param access_token [String] The project access token when pushing to LightStep
    # @param transport [LightStep::Transport] How the data should be transported
    # @param tags [Hash] Tracer-level tags
    # @return LightStep::Tracer
    # @raise LightStep::ConfigurationError if the group name or access token is not a valid string.
    def initialize(component_name:, access_token: nil, transport: nil, tags: {})
      configure(component_name: component_name, access_token: access_token, transport: transport, tags: tags)
    end

    def max_log_records
      @max_log_records ||= DEFAULT_MAX_LOG_RECORDS
    end

    def max_log_records=(max)
      @max_log_records = [MIN_MAX_LOG_RECORDS, max].max
    end

    def max_span_records
      @max_span_records ||= DEFAULT_MAX_SPAN_RECORDS
    end

    def max_span_records=(max)
      @max_span_records = [MIN_MAX_SPAN_RECORDS, max].max
      @reporter.max_span_records = @max_span_records
    end

    # Set the report flushing period. If set to 0, no flushing will be done, you
    # must manually call flush.
    def report_period_seconds=(seconds)
      @reporter.period = seconds
    end

    # TODO(bhs): Support FollowsFrom and multiple references

    # Creates a scope manager or returns the already-created one.
    #
    # @return [ScopeManager] the current ScopeManager, which may be a no-op but
    #   may not be nil.
    def scope_manager
      @scope_manager ||= LightStep::ScopeManager.new
    end

    # Returns a newly started and activated Scope.
    #
    # If ScopeManager#active is not nil, no explicit references are provided,
    # and `ignore_active_scope` is false, then an inferred References#CHILD_OF
    # reference is created to the ScopeManager#active's SpanContext when
    # start_active_span is invoked.
    #
    # @param operation_name [String] The operation name for the Span
    # @param child_of [SpanContext, Span] SpanContext that acts as a parent to
    #        the newly-started Span. If a Span instance is provided, its
    #        context is automatically substituted. See [Reference] for more
    #        information.
    #
    #   If specified, the `references` parameter must be omitted.
    # @param references [Array<Reference>] An array of reference
    #   objects that identify one or more parent SpanContexts.
    # @param start_time [Time] When the Span started, if not now
    # @param tags [Hash] Tags to assign to the Span at start time
    # @param ignore_active_scope [Boolean] whether to create an implicit
    #   References#CHILD_OF reference to the ScopeManager#active.
    # @param finish_on_close [Boolean] whether span should automatically be
    #   finished when Scope#close is called
    # @yield [Scope] If an optional block is passed to start_active_span it will
    #   yield the newly-started Scope. If `finish_on_close` is true then the
    #   Span will be finished automatically after the block is executed.
    # @return [Scope, Object] If passed an optional block, start_active_span
    #   returns the block's return value, otherwise it returns the newly-started
    #   and activated Scope
    def start_active_span(operation_name,
                          child_of: nil,
                          references: nil,
                          start_time: Time.now,
                          tags: nil,
                          ignore_active_scope: false,
                          finish_on_close: true)
      if child_of.nil? && references.nil? && !ignore_active_scope
        child_of = active_span
      end

      span = start_span(
        operation_name,
        child_of: child_of,
        references: references,
        start_time: start_time,
        tags: tags,
        ignore_active_scope: ignore_active_scope
      )

      scope_manager.activate(span: span, finish_on_close: finish_on_close).tap do |scope|
        if block_given?
          return yield(scope).tap do
            scope.close
          end
        end
      end
    end

    # Returns the span from the active scope, if any.
    #
    # @return [Span, nil] the active span. This is a shorthand for
    #   `scope_manager.active.span`, and nil will be returned if
    #   Scope#active is nil.
    def active_span
      scope = scope_manager.active
      scope.span if scope
    end

    # Starts a new span.
    #
    # @param operation_name [String] The operation name for the Span
    # @param child_of [SpanContext] SpanContext that acts as a parent to
    #        the newly-started Span. If a Span instance is provided, its
    #        .span_context is automatically substituted.
    # @param references [Array<SpanContext>] An array of SpanContexts that
    #         identify any parent SpanContexts of newly-started Span. If Spans
    #         are provided, their .span_context is automatically substituted.
    # @param start_time [Time] When the Span started, if not now
    # @param tags [Hash] Tags to assign to the Span at start time
    # @param ignore_active_scope [Boolean] whether to create an implicit
    #   References#CHILD_OF reference to the ScopeManager#active.
    # @yield [Span] If passed an optional block, start_span will yield the
    #   newly-created span to the block. The span will be finished automatically
    #   after the block is executed.
    # @return [Span, Object] If passed an optional block, start_span will return
    #  the block's return value, otherwise it returns the newly-started Span
    #  instance, which has not been automatically registered via the
    #  ScopeManager
    def start_span(operation_name, child_of: nil, references: nil, start_time: nil, tags: nil, ignore_active_scope: false)
      if child_of.nil? && references.nil? && !ignore_active_scope
        child_of = active_span
      end

      span_options = {
        tracer: self,
        operation_name: operation_name,
        child_of: child_of,
        references: references,
        start_micros: start_time.nil? ? LightStep.micros(Time.now) : LightStep.micros(start_time),
        tags: tags,
        max_log_records: max_log_records,
      }

      Span.new(span_options).tap do |span|
        if block_given?
          return yield(span).tap do
            span.finish
          end
        end
      end
    end

    # Inject a SpanContext into the given carrier
    #
    # @param spancontext [SpanContext]
    # @param format [OpenTracing::FORMAT_TEXT_MAP, OpenTracing::FORMAT_BINARY]
    # @param carrier [Carrier] A carrier object of the type dictated by the specified `format`
    def inject(span_context, format, carrier)
      case format
      when OpenTracing::FORMAT_TEXT_MAP
        inject_to_text_map(span_context, carrier)
      when OpenTracing::FORMAT_BINARY
        warn 'Binary inject format not yet implemented'
      when OpenTracing::FORMAT_RACK
        inject_to_rack(span_context, carrier)
      else
        warn 'Unknown inject format'
      end
    end

    # Extract a SpanContext from a carrier
    # @param format [OpenTracing::FORMAT_TEXT_MAP, OpenTracing::FORMAT_BINARY, OpenTracing::FORMAT_RACK]
    # @param carrier [Carrier] A carrier object of the type dictated by the specified `format`
    # @return [SpanContext] the extracted SpanContext or nil if none could be found
    def extract(format, carrier)
      case format
      when OpenTracing::FORMAT_TEXT_MAP
        extract_from_text_map(carrier)
      when OpenTracing::FORMAT_BINARY
        warn 'Binary join format not yet implemented'
        nil
      when OpenTracing::FORMAT_RACK
        extract_from_rack(carrier)
      else
        warn 'Unknown join format'
        nil
      end
    end

    # @return true if the tracer is enabled
    def enabled?
      return @enabled if defined?(@enabled)
      @enabled = true
    end

    # Enables the tracer
    def enable
      @enabled = true
    end

    # Disables the tracer
    # @param discard [Boolean] whether to discard queued data
    def disable(discard: true)
      @enabled = false
      @reporter.clear if discard
      @reporter.flush
    end

    # Flush to the Transport
    def flush
      return unless enabled?
      @reporter.flush
    end

    # Internal use only.
    # @private
    def finish_span(span)
      return unless enabled?
      @reporter.add_span(span)
    end

    protected

    def configure(component_name:, access_token: nil, transport: nil, tags: {})
      raise ConfigurationError, "component_name must be a string" unless component_name.is_a?(String)
      raise ConfigurationError, "component_name cannot be blank"  if component_name.empty?

      if transport.nil? and !access_token.nil?
        transport = Transport::HTTPJSON.new(access_token: access_token)
      end

      raise ConfigurationError, "you must provide an access token or a transport" if transport.nil?
      raise ConfigurationError, "#{transport} is not a LightStep transport class" if !(LightStep::Transport::Base === transport)

      @guid = LightStep.guid

      @reporter = LightStep::Reporter.new(
        max_span_records: max_span_records,
        transport: transport,
        guid: guid,
        component_name: component_name,
        tags: tags
      )
    end

    private

    CARRIER_TRACER_STATE_PREFIX = 'ot-tracer-'.freeze
    CARRIER_BAGGAGE_PREFIX = 'ot-baggage-'.freeze

    CARRIER_SPAN_ID = (CARRIER_TRACER_STATE_PREFIX + 'spanid').freeze
    CARRIER_TRACE_ID = (CARRIER_TRACER_STATE_PREFIX + 'traceid').freeze
    CARRIER_SAMPLED = (CARRIER_TRACER_STATE_PREFIX + 'sampled').freeze

    DEFAULT_MAX_LOG_RECORDS = 1000
    MIN_MAX_LOG_RECORDS = 1
    DEFAULT_MAX_SPAN_RECORDS = 1000
    MIN_MAX_SPAN_RECORDS = 1

    TRACE_PARENT = 'traceparent'.freeze
    TRACE_PARENT_VERSION = 0
    TRACE_PARENT_REGEX = /\h{2}-(\h{32})-(\h{16})-\h{2}/

    TRACE_STATE = 'tracestate'.freeze
    TRACE_STATE_VENDOR = 'lightstep'.freeze
    MAX_TRACE_STATE_SIZE = 512

    def inject_to_text_map(span_context, carrier)
      carrier[CARRIER_SPAN_ID] = span_context.id
      carrier[CARRIER_TRACE_ID] = span_context.trace_id unless span_context.trace_id.nil?
      carrier[CARRIER_SAMPLED] = 'true'

      span_context.baggage.each do |key, value|
        carrier[CARRIER_BAGGAGE_PREFIX + key] = value
      end
    end

    def extract_from_text_map(carrier)
      trace_id = carrier[CARRIER_TRACE_ID]
      id = carrier[CARRIER_SPAN_ID]

      if trace_id.nil? || trace_id.empty? || id.nil? || id.empty?
        matches = TRACE_PARENT_REGEX.match(carrier[TRACE_PARENT])
        unless matches.nil?
          trace_id = matches[1]
          id = matches[2]
        end
      end

      # If the carrier does not have both the span_id and trace_id key
      # skip the processing and just return a normal span
      if trace_id.nil? || trace_id.empty? || id.nil? || id.empty?
        return nil
      end

      baggage = carrier.reduce({}) do |baggage, tuple|
        key, value = tuple
        if key.start_with?(CARRIER_BAGGAGE_PREFIX)
          plain_key = key.to_s[CARRIER_BAGGAGE_PREFIX.length..key.to_s.length]
          baggage[plain_key] = value
        end
        baggage
      end

      trace_state = (carrier[TRACE_STATE] || '').split(',')
        .map { |item| item.match(/^(.*)=(.*)$/).captures }
        .find_all { |vendor, state| !vendor.nil? && !vendor.empty? && !state.nil? }
        .reduce([]) do |memo, (vendor, value)|
          if vendor == TRACE_STATE_VENDOR
            baggage = baggage.merge(decode_tracestate_baggage(value))
          else
            memo << "#{vendor}=#{value}"
          end

          memo
        end

      SpanContext.new(
        id: id,
        trace_id: trace_id,
        baggage: baggage,
        trace_state: trace_state
      )
    end

    def inject_to_rack(span_context, carrier)
      carrier[CARRIER_SPAN_ID] = span_context.id
      carrier[CARRIER_TRACE_ID] = span_context.trace_id unless span_context.trace_id.nil?
      carrier[CARRIER_SAMPLED] = 'true'
      carrier[TRACE_PARENT] = format('%<version>02x-%<trace_id>s-%<span_id>s-01', {
        version: TRACE_PARENT_VERSION,
        trace_id: span_context.trace_id.rjust(32, '0'),
        span_id: span_context.id.rjust(16, '0')
      })

      span_context.baggage.sort.each do |key, value|
        if key =~ /[^A-Za-z0-9\-_]/
          # TODO: log the error internally
          next
        end

        carrier[CARRIER_BAGGAGE_PREFIX + key] = value
      end

      encoded_baggage = ''

      unless span_context.baggage.empty?
        encoded_baggage = Base64.urlsafe_encode64(JSON.generate(span_context.baggage), padding: false)
      end

      trace_state = "#{TRACE_STATE_VENDOR}=#{encoded_baggage}"

      for item in span_context.trace_state
        if trace_state.length + item.length + 1 > MAX_TRACE_STATE_SIZE
          break
        end

        trace_state << ',' << item
      end

      carrier[TRACE_STATE] = trace_state
    end

    def extract_from_rack(env)
      extract_from_text_map(env.reduce({}){|memo, tuple|
        raw_header, value = tuple
        header = raw_header.to_s.gsub(/^HTTP_/, '').tr('_', '-').downcase

        memo[header] = value if header.start_with?(CARRIER_TRACER_STATE_PREFIX, CARRIER_BAGGAGE_PREFIX) || header == TRACE_PARENT || header == TRACE_STATE
        memo
      })
    end

    def decode_tracestate_baggage(value)
      begin
        decoded_baggage = Base64.urlsafe_decode64(value || '')
      rescue ArgumentError
        decoded_baggage = nil
      end

      JSON.parse(decoded_baggage)
    end
  end
end
