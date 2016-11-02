require 'json'
require 'concurrent'

require 'lightstep/span'
require 'lightstep/transport/http_json'
require 'lightstep/transport/nil'
require 'lightstep/transport/callback'

module LightStep
  class Tracer
    FORMAT_TEXT_MAP = 1
    FORMAT_BINARY = 2

    CARRIER_TRACER_STATE_PREFIX = 'ot-tracer-'.freeze
    CARRIER_BAGGAGE_PREFIX = 'ot-baggage-'.freeze

    DEFAULT_MAX_LOG_RECORDS = 1000
    MIN_MAX_LOG_RECORDS = 1
    DEFAULT_MAX_SPAN_RECORDS = 1000
    MIN_MAX_SPAN_RECORDS = 1
    DEFAULT_MIN_REPORTING_PERIOD_SECS = 1.5
    DEFAULT_MAX_REPORTING_PERIOD_SECS = 30.0

    class Error < LightStep::Error; end
    class ConfigurationError < LightStep::Tracer::Error; end

    attr_reader :access_token, :guid

    # Initialize a new tracer. Either an access_token or a transport must be
    # provided. A component_name is always required.
    # @param component_name [String] Component name to use for the tracer
    # @param access_token [String] The project access token when pushing to LightStep
    # @param transport [LightStep::Transport] How the data should be transported
    # @return LightStep::Tracer
    # @raise LightStep::ConfigurationError if the group name or access token is not a valid string.
    def initialize(component_name:, access_token: nil, transport: nil)
      configure(component_name: component_name, access_token: access_token, transport: transport)
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
    end

    def min_flush_period_micros
      @min_flush_period_micros ||= DEFAULT_MIN_REPORTING_PERIOD_SECS * 1E6
    end

    def max_flush_period_micros
      @max_flush_period_micros ||= DEFAULT_MAX_REPORTING_PERIOD_SECS * 1E6
    end

    # TODO(ngauthier@gmail.com) inherit SpanContext from references

    # Starts a new span.
    # @param operation_name [String] the operation name for the Span
    # @param child_of [Span] Span to inherit from
    # @param start_time [Time] When the Span started, if not now
    # @param tags [Hash] tags for the span
    # @return [Span]
    def start_span(operation_name, child_of: nil, start_time: nil, tags: nil)
      child_of_guid = nil
      trace_guid = nil
      if Span === child_of
        child_of_guid = child_of.guid
        trace_guid = child_of.trace_guid
      else
        trace_guid = LightStep.guid
      end

      Span.new(
        tracer: self,
        operation_name: operation_name,
        child_of_guid: child_of_guid,
        trace_guid: trace_guid,
        start_micros: start_time.nil? ? LightStep.micros(Time.now) : LightStep.micros(start_time),
        tags: tags,
        max_log_records: max_log_records
      )
    end

    # Inject a span into the given carrier
    # @param span [Span]
    # @param format [LightStep::Tracer::FORMAT_TEXT_MAP, LightStep::Tracer::FORMAT_BINARY]
    # @param carrier [Hash-like]
    def inject(span, format, carrier)
      case format
      when LightStep::Tracer::FORMAT_TEXT_MAP
        inject_to_text_map(span, carrier)
      when LightStep::Tracer::FORMAT_BINARY
        warn 'Binary inject format not yet implemented'
      else
        warn 'Unknown inject format'
      end
    end

    # Extract a span from a carrier
    # @param operation_name [String]
    # @param format [LightStep::Tracer::FORMAT_TEXT_MAP, LightStep::Tracer::FORMAT_BINARY]
    # @param carrier [Hash-like]
    # @return [Span]
    def extract(operation_name, format, carrier)
      case format
      when LightStep::Tracer::FORMAT_TEXT_MAP
        extract_from_text_map(operation_name, carrier)
      when LightStep::Tracer::FORMAT_BINARY
        warn 'Binary join format not yet implemented'
        nil
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
      @transport.clear if discard
      @transport.flush
    end

    # Flush to the Transport
    def flush
      _flush_worker
    end

    # Internal use only.
    # @private
    def finish_span(span)
      return unless enabled?
      @span_records.push(span.to_h)
      if @span_records.size > max_span_records
        @span_records.shift
        @dropped_spans.increment
        @dropped_span_logs.increment(span.logs_count + span.dropped_logs_count)
      end
      flush_if_needed
    end

    protected

    def access_token=(token)
      if !access_token.nil?
        raise ConfigurationError, "access token cannot be changed"
      end
      @access_token = token
    end

    def configure(component_name:, access_token: nil, transport: nil)
      raise ConfigurationError, "component_name must be a string" unless String === component_name
      raise ConfigurationError, "component_name cannot be blank"  if component_name.empty?

      @span_records = Concurrent::Array.new
      @dropped_spans = Concurrent::AtomicFixnum.new
      @dropped_span_logs = Concurrent::AtomicFixnum.new

      start_time = LightStep.micros(Time.now)
      @guid = LightStep.guid
      @report_start_time = start_time
      @last_flush_micros = start_time

      @runtime = {
        guid: guid,
        start_micros: start_time,
        group_name: component_name,
        attrs: [
          {Key: "lightstep.tracer_platform",         Value: "ruby"},
          {Key: "lightstep.tracer_version",          Value: LightStep::VERSION},
          {Key: "lightstep.tracer_platform_version", Value: RUBY_VERSION}
        ]
      }.freeze

      if !transport.nil?
        if !(LightStep::Transport::Base === transport)
          raise ConfigurationError, "transport is not a LightStep transport class: #{transport}"
        end
        @transport = transport
      else
        if access_token.nil?
          raise ConfigurationError, "you must provide an access token or a transport"
        end
        @transport = Transport::HTTPJSON.new(access_token: access_token)
      end

      # At exit, flush this objects data to the transport and close the transport
      # (which in turn will send the flushed data over the network).
      at_exit do
        flush
        @transport.close
      end
    end

    def flush_if_needed
      return unless enabled?

      delta = LightStep.micros(Time.now) - @last_flush_micros
      return if delta < min_flush_period_micros

      if delta > max_flush_period_micros || @span_records.size >= max_span_records / 2
        flush
      end
    end

    private

    def inject_to_text_map(span, carrier)
      carrier[CARRIER_TRACER_STATE_PREFIX + 'spanid'] = span.guid
      carrier[CARRIER_TRACER_STATE_PREFIX + 'traceid'] = span.trace_guid unless span.trace_guid.nil?
      carrier[CARRIER_TRACER_STATE_PREFIX + 'sampled'] = 'true'

      span.baggage.each do |key, value|
        carrier[CARRIER_BAGGAGE_PREFIX + key] = value
      end
    end

    def extract_from_text_map(operation_name, carrier)
      span = Span.new(
        tracer: self,
        operation_name: operation_name,
        start_micros: LightStep.micros(Time.now),
        child_of_guid: carrier[CARRIER_TRACER_STATE_PREFIX + 'spanid'],
        trace_guid: carrier[CARRIER_TRACER_STATE_PREFIX + 'traceid'],
        max_log_records: max_log_records
      )

      carrier.each do |key, value|
        next unless key.start_with?(CARRIER_BAGGAGE_PREFIX)
        plain_key = key.to_s[CARRIER_BAGGAGE_PREFIX.length..key.to_s.length]
        span.set_baggage_item(plain_key, value)
      end
      span
    end

    def _flush_worker
      return unless enabled?
      # The thrift configuration has not yet been set: allow logs and spans
      # to be buffered in this case, but flushes won't yet be possible.
      return if @runtime.nil?
      return if @span_records.empty?

      now = LightStep.micros(Time.now)

      span_records = @span_records.slice!(0, @span_records.length)
      dropped_spans = 0
      @dropped_spans.update{|old| dropped_spans = old; 0 }

      old_dropped_span_logs = 0
      @dropped_span_logs.update{|old| old_dropped_span_logs = old; 0 }
      dropped_logs = old_dropped_span_logs
      dropped_logs = span_records.reduce(dropped_logs) do |memo, span|
        memo += span.delete :dropped_logs
      end

      report_request = {
        runtime: @runtime,
        oldest_micros: @report_start_time,
        youngest_micros: now,
        span_records: span_records,
        counters: [
            {Name: "dropped_logs",  Value: dropped_logs},
            {Name: "dropped_spans", Value: dropped_spans},
        ]
      }

      @last_flush_micros = now
      @report_start_time = now

      begin
        @transport.report(report_request)
      rescue LightStep::Transport::HTTPJSON::QueueFullError
        # If the queue is full, add the previous dropped logs to the logs
        # that were going to get reported, as well as the previous dropped
        # spans and spans that would have been recorded
        @dropped_spans.increment(dropped_spans + span_records.length)
        @dropped_span_logs.increment(old_dropped_span_logs)
      end
    end
  end
end
