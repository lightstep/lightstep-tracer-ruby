require 'json'
require 'concurrent'

require 'lightstep/span'
require 'lightstep/reporter'
require 'lightstep/transport/http_json'
require 'lightstep/transport/nil'
require 'lightstep/transport/callback'

module LightStep
  class Tracer
    FORMAT_TEXT_MAP = 1
    FORMAT_BINARY = 2
    FORMAT_RACK = 3

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

    # Starts a new span.
    #
    # @param operation_name [String] The operation name for the Span
    # @param child_of [SpanContext] SpanContext that acts as a parent to
    #        the newly-started Span. If a Span instance is provided, its
    #        .span_context is automatically substituted.
    # @param start_time [Time] When the Span started, if not now
    # @param tags [Hash] Tags to assign to the Span at start time
    # @return [Span]
    def start_span(operation_name, child_of: nil, start_time: nil, tags: nil)
      span = Span.new(
        tracer: self,
        operation_name: operation_name,
        child_of: child_of,
        start_micros: start_time.nil? ? LightStep.micros(Time.now) : LightStep.micros(start_time),
        tags: tags,
        max_log_records: max_log_records,
      )

      span
    end

    # Inject a SpanContext into the given carrier
    #
    # @param spancontext [SpanContext]
    # @param format [LightStep::Tracer::FORMAT_TEXT_MAP, LightStep::Tracer::FORMAT_BINARY]
    # @param carrier [Hash]
    def inject(span_context, format, carrier)
      case format
      when LightStep::Tracer::FORMAT_TEXT_MAP
        inject_to_text_map(span_context, carrier)
      when LightStep::Tracer::FORMAT_BINARY
        warn 'Binary inject format not yet implemented'
      when LightStep::Tracer::FORMAT_RACK
        inject_to_rack(span_context, carrier)
      else
        warn 'Unknown inject format'
      end
    end

    # Extract a SpanContext from a carrier
    # @param format [LightStep::Tracer::FORMAT_TEXT_MAP, LightStep::Tracer::FORMAT_BINARY]
    # @param carrier [Hash]
    # @return [SpanContext] the extracted SpanContext or nil if none could be found
    def extract(format, carrier)
      case format
      when LightStep::Tracer::FORMAT_TEXT_MAP
        extract_from_text_map(carrier)
      when LightStep::Tracer::FORMAT_BINARY
        warn 'Binary join format not yet implemented'
        nil
      when LightStep::Tracer::FORMAT_RACK
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
      raise ConfigurationError, "component_name must be a string" unless String === component_name
      raise ConfigurationError, "component_name cannot be blank"  if component_name.empty?

      transport = Transport::HTTPJSON.new(access_token: access_token) if !access_token.nil?
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

    def inject_to_text_map(span_context, carrier)
      carrier[CARRIER_SPAN_ID] = span_context.id
      carrier[CARRIER_TRACE_ID] = span_context.trace_id unless span_context.trace_id.nil?
      carrier[CARRIER_SAMPLED] = 'true'

      span_context.baggage.each do |key, value|
        carrier[CARRIER_BAGGAGE_PREFIX + key] = value
      end
    end

    def extract_from_text_map(carrier)
      # If the carrier does not have both the span_id and trace_id key
      # skip the processing and just return a normal span
      if !carrier.has_key?(CARRIER_SPAN_ID) || !carrier.has_key?(CARRIER_TRACE_ID)
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
      span_context = SpanContext.new(
        id: carrier[CARRIER_SPAN_ID],
        trace_id: carrier[CARRIER_TRACE_ID],
        baggage: baggage,
      )
      span_context
    end

    def inject_to_rack(span_context, carrier)
      carrier[CARRIER_SPAN_ID] = span_context.id
      carrier[CARRIER_TRACE_ID] = span_context.trace_id unless span_context.trace_id.nil?
      carrier[CARRIER_SAMPLED] = 'true'

      span_context.baggage.each do |key, value|
        if key =~ /[^A-Za-z0-9\-_]/
          # TODO: log the error internally
          next
        end
        carrier[CARRIER_BAGGAGE_PREFIX + key] = value
      end
    end

    def extract_from_rack(env)
      extract_from_text_map(env.reduce({}){|memo, tuple|
        raw_header, value = tuple
        header = raw_header.gsub(/^HTTP_/, '').gsub("_", "-").downcase

        memo[header] = value if header.start_with?(CARRIER_TRACER_STATE_PREFIX, CARRIER_BAGGAGE_PREFIX)
        memo
      })
    end
  end
end
