require 'json'

require 'lightstep/tracer/span'
require 'lightstep/tracer/transport/http_json'
require 'lightstep/tracer/transport/nil'
require 'lightstep/tracer/transport/callback'

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

    attr_reader :access_token

    # ----------------------------------------------------------------------------
    # Implemenation specific
    # ----------------------------------------------------------------------------

    # Initialize a new tracer. Either an access_token or a transport must be
    # provided. A component_name is always required.
    # @param $component_name Component name to use for the tracer
    # @param $access_token The project access token when pushing to LightStep
    # @param $transport LightStep::Transport to use
    # @return LightStepBase_Tracer
    # @throws LightStep::ConfigurationError if the group name or access token is not a valid string.
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

    def min_reporting_period_secs=(secs)
      @min_flush_period_micros = [DEFAULT_MIN_REPORTING_PERIOD_SECS, secs].max * 1E6
    end

    def max_flush_period_micros
      @max_flush_period_micros ||= DEFAULT_MAX_REPORTING_PERIOD_SECS * 1E6
    end

    def max_reporting_period_secs=(secs)
      @max_flush_period_micros = [DEFAULT_MAX_REPORTING_PERIOD_SECS, secs].min * 1E6
    end

    # Starts a new span.
    # TODO(ngauthier@gmail.com) inherit SpanContext from references
    def start_span(operation_name, child_of: nil, start_time: nil, tags: nil)
      child_of_guid = nil
      trace_guid = nil
      if Span === child_of
        child_of_guid = child_of.guid
        trace_guid = child_of.trace_guid
      else
        trace_guid = generate_guid
      end

      Span.new(
        tracer: self,
        operation_name: operation_name,
        child_of_guid: child_of_guid,
        trace_guid: trace_guid,
        start_micros: start_time.nil? ? now_micros : micros(start_time),
        tags: tags
      )
    end

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

    def join(operation_name, format, carrier)
      case format
      when LightStep::Tracer::FORMAT_TEXT_MAP
        join_from_text_map(operation_name, carrier)
      when LightStep::Tracer::FORMAT_BINARY
        warn 'Binary join format not yet implemented'
        nil
      else
        warn 'Unknown join format'
        nil
      end
    end

    # The GUID of the tracer
    def guid
      @guid ||= generate_guid
    end

    # @return true if the tracer is enabled
    def enabled?
      @enabled ||= true
    end

    # Enables the tracer
    def enable
      @enabled = true
    end

    # Disables the tracer
    # @param discard [Boolean] whether to discard queued data
    def disable(discard: true)
      @enabled = false
      @tracer_transport.clear if discard
      @tracer_transport.flush
    end

    def flush
      _flush_worker
    end

    # Internal use only.
    def _finish_span(span, end_time: Time.now)
      return unless enabled?

      span.end_micros ||= micros(end_time)
      full = push_with_max(@tracer_span_records, span.to_h, max_span_records)
      @tracer_counters[:dropped_spans] += 1 if full
      flush_if_needed
    end

    def raw_log_record(fields, payload)
      return unless enabled?

      fields['runtime_guid'] = guid

      if fields['timestamp_micros'].nil?
        fields['timestamp_micros'] = now_micros
      end

      # TODO: data scrubbing and size limiting
      json = nil
      case payload
      when Array, Hash
        begin
          fields['payload_json'] = JSON.generate(payload, max_nesting: 8)
        rescue
          # TODO(ngauthier@gmail.com) naked rescue
          # TODO: failure to encode a payload as JSON should be recorded in the
          # internal library logs, with catioun not flooding the internal logs.
        end
      when nil
        # noop
      else
        # TODO: Remove the outer 'payload' key wrapper. Just transport the JSON
        # Value (Value in the sense of the JSON spec).
        fields['payload_json'] = JSON.generate(payload: payload)
      end

      full = push_with_max(@tracer_log_records, fields, max_log_records)
      @tracer_counters[:dropped_logs] += 1 if full
    end

    # Returns a random guid. Note: this intentionally does not use SecureRandom,
    # which is slower and cryptographically secure randomness is not required here.
    def generate_guid
      @_rng ||= Random.new
      @_rng.bytes(8).unpack('H*')[0]
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

      @tracer_log_records = []
      @tracer_span_records = []
      @tracer_counters = {
        dropped_logs: 0,
        dropped_spans: 0
      }

      start_time = now_micros.to_i
      @tracer_report_start_time = start_time
      @tracer_last_flush_micros = start_time

      @tracer_thrift_runtime = {
        'guid' => guid,
        'start_micros' => start_time,
        'group_name' => component_name,
        'attrs' => [
          {"Key" => "lightstep_tracer_platform", "Value" => "ruby"},
          {"Key" => "lightstep_tracer_version",  "Value" => LightStep::Tracer::VERSION},
          {"Key" => "ruby_version",              "Value" => RUBY_VERSION}
        ]
      }.freeze

      if !transport.nil?
        if !(LightStep::Transport::Base === transport)
          raise ConfigurationError, "transport is not a LightStep transport class: #{transport}"
        end
        @tracer_transport = transport
      else
        if access_token.nil?
          raise ConfigurationError, "you must provide an access token or a transport"
        end
        @tracer_transport = Transport::HTTPJSON.new(access_token: access_token)
      end

      # At exit, flush this objects data to the transport and close the transport
      # (which in turn will send the flushed data over the network).
      at_exit do
        flush
        @tracer_transport.close
      end
    end

    def push_with_max(arr, item, max)
      max = 1 unless max > 0

      arr << item

      # Simplistic random discard
      count = arr.size
      if count > max
        i = rand(0..(max - 2)) # rand(a..b) is inclusive
        arr[i] = arr.pop
        return true
      else
        return false
      end
    end

    def flush_if_needed
      return unless enabled?

      delta = now_micros - @tracer_last_flush_micros

      # Set a bound on maximum flush frequency
      return if delta < min_flush_period_micros

      # Look for a trigger that a flush is warranted
      # Set a bound of minimum flush frequency
      if delta > max_flush_period_micros ||
         @tracer_log_records.length >= max_log_records / 2 ||
         @tracer_span_records.length >= max_span_records / 2
        flush
      end
    end

    def now_micros
      micros(Time.now)
    end

    private

    def micros(time)
      (time.to_f * 1E6).floor
    end

    def inject_to_text_map(span, carrier)
      carrier[CARRIER_TRACER_STATE_PREFIX + 'spanid'] = span.guid
      carrier[CARRIER_TRACER_STATE_PREFIX + 'traceid'] = span.trace_guid unless span.trace_guid.nil?
      carrier[CARRIER_TRACER_STATE_PREFIX + 'sampled'] = 'true'

      span.baggage.each do |key, value|
        carrier[CARRIER_BAGGAGE_PREFIX + key] = value
      end
    end

    def join_from_text_map(operation_name, carrier)
      span = Span.new(
        tracer: self,
        operation_name: operation_name,
        start_micros: now_micros,
        child_of_guid: carrier[CARRIER_TRACER_STATE_PREFIX + 'spanid'],
        trace_guid: carrier[CARRIER_TRACER_STATE_PREFIX + 'traceid'],
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

      now = now_micros

      # The thrift configuration has not yet been set: allow logs and spans
      # to be buffered in this case, but flushes won't yet be possible.
      return if @tracer_thrift_runtime.nil?

      return if @tracer_log_records.empty? && @tracer_span_records.empty?

      # Convert the counters to thrift form
      thrift_counters = @tracer_counters.map do |key, value|
        {"Name" => key.to_s, "Value" => value.to_i}
      end

      report_request = {
        'runtime' => @tracer_thrift_runtime,
        'oldest_micros' => @tracer_report_start_time.to_i,
        'youngest_micros' => now.to_i,
        'log_records' => @tracer_log_records,
        'span_records' => @tracer_span_records,
        'counters' => thrift_counters
      }

      @tracer_last_flush_micros = now

      resp = @tracer_transport.report(report_request)

      # ALWAYS reset the buffers and update the counters as the RPC response
      # is, by design, not waited for and not reliable.
      @tracer_report_start_time = now
      @tracer_log_records = []
      @tracer_span_records = []
      @tracer_counters.each do |key, _value|
        @tracer_counters[key] = 0
      end

      # Process server response commands
      if !resp.nil? && Array === resp.commands
        resp.commands.each do |cmd|
          disable if cmd.disable
        end
      end
    end
  end
end
