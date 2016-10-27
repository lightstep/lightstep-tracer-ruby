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

    class Error < StandardError; end
    class ConfigurationError < LightStep::Tracer::Error; end

    attr_reader :access_token

    # ----------------------------------------------------------------------------
    # Implemenation specific
    # ----------------------------------------------------------------------------

    # TODO(ngauthier@gmail.com) document all options, convert to keyword args
    # Creates a new tracer instance.
    #
    # @param $component_name Component name to use for the tracer
    # @param $access_token The project access token
    # @return LightStepBase_Tracer
    # @throws Exception if the group name or access token is not a valid string.
    def initialize(options = {})
      configure(options)
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

    # ----------------------------------------------------------------------------
    #  OpenTracing API
    # ----------------------------------------------------------------------------

    # Starts a new span.
    #
    # The fields argument is optional. The accepted fields are:
    #
    # :parent - parent span object
    # :tags - map of key-value pairs
    # :startTime - manually specified start time of the span in milliseconds
    # :endTime - manually specified end time of the span in milliseconds
    #
    # TODO(ngauthier@gmail.com) parent should be child_of according to spec
    # TODO(ngauthier@gmail.com) support follows_from?
    # TODO(ngauthier@gmail.com) follows_from and child_of should be `references`
    # TODO(ngauthier@gmail.com) inherit SpanContext from references
    # TODO(ngauthier@gmail.com) fields should be tags
    # TODO(ngauthier@gmail.com) ability to provide a timestamp to be used other than now
    def start_span(operation_name, fields = nil)
      span = Span.new(self)
      span.set_operation_name(operation_name)
      span.set_start_micros(now_micros)

      unless fields.nil?
        span.set_parent(fields[:parent]) unless fields[:parent].nil?
        span.set_tags(fields[:tags]) unless fields[:tags].nil?
        span.set_start_micros(fields[:startTime] * 1000) unless fields[:startTime].nil?
        span.set_end_micros(fields[:endTime] * 1000) unless fields[:endTime].nil?
      end

      span.trace_guid = generate_guid if span.trace_guid.nil?
      span
    end

    def inject(span, format, carrier)
      case format
      when LightStep::Tracer::FORMAT_TEXT_MAP
        _inject_to_text_map(span, carrier)
      when LightStep::Tracer::FORMAT_BINARY
        warn 'Binary inject format not yet implemented'
      else
        warn 'Unknown inject format'
      end
    end

    def join(operation_name, format, carrier)
      case format
      when LightStep::Tracer::FORMAT_TEXT_MAP
        _join_from_text_map(operation_name, carrier)
      when LightStep::Tracer::FORMAT_BINARY
        warn 'Binary join format not yet implemented'
        nil
      else
        warn 'Unknown join format'
        nil
      end
    end



    # FIXME(ngauthier@gmail.com) private
    def _inject_to_text_map(span, carrier)
      carrier[LightStep::Tracer::CARRIER_TRACER_STATE_PREFIX + 'spanid'] = span.guid
      carrier[LightStep::Tracer::CARRIER_TRACER_STATE_PREFIX + 'traceid'] = span.trace_guid unless span.trace_guid.nil?
      carrier[LightStep::Tracer::CARRIER_TRACER_STATE_PREFIX + 'sampled'] = 'true'

      span.baggage.each do |key, value|
        carrier[LightStep::Tracer::CARRIER_BAGGAGE_PREFIX + key] = value
      end
    end

    # FIXME(ngauthier@gmail.com) private
    def _join_from_text_map(operation_name, carrier)
      span = Span.new(self)
      span.set_operation_name(operation_name)
      span.set_start_micros(now_micros)

      parent_guid = carrier[LightStep::Tracer::CARRIER_TRACER_STATE_PREFIX + 'spanid']
      trace_guid = carrier[LightStep::Tracer::CARRIER_TRACER_STATE_PREFIX + 'traceid']
      span.trace_guid = trace_guid
      span.set_tag(:parent_span_guid, parent_guid)

      carrier.each do |key, value|
        next unless key.start_with?(LightStep::Tracer::CARRIER_BAGGAGE_PREFIX)
        plain_key = key.to_s[LightStep::Tracer::CARRIER_BAGGAGE_PREFIX.length..key.to_s.length]
        span.set_baggage_item(plain_key, value)
      end
      span
    end

    def guid
      @_guid ||= generate_guid
    end

    # @return true if the tracer is enabled
    def enabled?
      @_enabled ||= true
    end

    # Enables the tracer
    def enable
      @_enabled = true
    end

    # Disables the tracer
    # @param discard [Boolean] whether to discard queued data
    def disable(discard: false)
      @_enabled = false
      @tracer_transport.close(discard)
    end

    def flush
      _flush_worker
    end

    # FIXME(ngauthier@gmail.com) private
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

      resp = @tracer_transport.flush_report(@tracer_thrift_auth, report_request)

      # ALWAYS reset the buffers and update the counters as the RPC response
      # is, by design, not waited for and not reliable.
      @tracer_report_start_time = now
      @tracer_log_records = []
      @tracer_span_records = []
      @tracer_counters.each do |key, _value|
        @tracer_counters[key] = 0
      end

      # Process server response commands
      # FIXME(ngauthier@gmail.com) triple equals
      if !resp.nil? && resp.commands.class.name == 'Array'
        resp.commands.each do |cmd|
          disable if cmd.disable
        end
      end
    end

    # Internal use only.
    def _finish_span(span)
      return unless enabled?

      span.set_end_micros(now_micros) if span.end_micros === 0
      full = push_with_max(@tracer_span_records, span.to_thrift, max_span_records)
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
      # FIXME(ngauthier@gmail.com) triple equals
      # FIXME(ngauthier@gmail.com) can do as a type case
      if payload.is_a?(Array) || payload.is_a?(Hash)
        begin
          json = JSON.generate(payload, max_nesting: 8)
        rescue
          # TODO: failure to encode a payload as JSON should be recorded in the
          # internal library logs, with catioun not flooding the internal logs.
        end
      elsif !payload.nil?
        # TODO: Remove the outer 'payload' key wrapper. Just transport the JSON
        # Value (Value in the sense of the JSON spec).
        json = JSON.generate(payload: payload)
      end
      # FIXME(ngauthier@gmail.com) triple equal String
      fields['payload_json'] = json if json.class.name == 'String'

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

    def configure(
      component_name:,
      access_token:,
      collector_host: 'collector.lightstep.com',
      collector_port: nil,
      collector_secure: true,
      collector_encryption: 'tls',
      transport: 'http_json',
      transport_callback: nil,

      # Internal debugging flag that enables additional logging and
      # tracer checks. Not intended to run in production as it may add
      # logging "noise" to the calling code.
      verbose: 0
    )
      raise ConfigurationError, "component_name must be a string" unless String === component_name
      raise ConfigurationError, "component_name cannot be blank"  if component_name.empty?

      raise ConfigurationError, "access_token must be a string" unless String === access_token
      raise ConfigurationError, "access_token cannot be blank"  if access_token.empty?

      @tracer_log_records = []
      @tracer_span_records = []
      @tracer_counters = {
        dropped_logs: 0,
        dropped_spans: 0
      }

      self.access_token = access_token

      start_time = now_micros.to_i
      @tracer_report_start_time = start_time
      @tracer_last_flush_micros = start_time

      @tracer_thrift_auth = {"access_token" => access_token}
      @tracer_thrift_runtime = {
        'guid' => guid,
        'start_micros' => start_time,
        'group_name' => component_name,
        'attrs' => [
          {"Key" => "lightstep_tracer_platform", "Value" => "ruby"},
          {"Key" => "lightstep_tracer_version",  "Value" => LightStep::Tracer::VERSION},
          {"Key" => "ruby_version",              "Value" => RUBY_VERSION}
        ]
      }

      @tracer_transport = nil
      case transport
      when 'nil'
        @tracer_transport = Transport::Nil.new
      when 'callback'
        @tracer_transport = Transport::Callback.new(callback: transport_callback)
      when 'http_json'
        collector_port ||= collector_secure ? 443 : 80
        @tracer_transport = Transport::HTTPJSON.new(
          host: collector_host,
          port: collector_port,
          verbose: verbose,
          secure: collector_encryption != 'none'
        )
      else
        raise ConfigurationError, "unknown transport #{transport}"
      end

      # At exit, flush this objects data to the transport and close the transport
      # (which in turn will send the flushed data over the network).
      at_exit do
        flush
        @tracer_transport.close(false)
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
      (Time.now.to_f * 1e6).floor
    end
  end
end
