require 'json'
require 'weakref'

require_relative './constants'
require_relative './client_span'
require_relative './util'
require_relative './transports/transport_http_json'
require_relative './transports/transport_nil'
require_relative './transports/transport_callback'
require_relative './thrift/crouton_types'
require_relative './version.rb'

class ClientTracer
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
  def start_span(operation_name, fields = nil)
    span = ClientSpan.new(self)
    span.set_operation_name(operation_name)
    span.set_start_micros(@tracer_utils.now_micros)

    unless fields.nil?
      span.set_parent(fields[:parent]) unless fields[:parent].nil?
      span.set_tags(fields[:tags]) unless fields[:tags].nil?
      span.set_start_micros(fields[:startTime] * 1000) unless fields[:startTime].nil?
      span.set_end_micros(fields[:endTime] * 1000) unless fields[:endTime].nil?
    end

    span.trace_guid = generate_uuid_string if span.trace_guid.nil?
    span
  end

  def inject(span, format, carrier)
    case format
    when Lightstep::Tracer::FORMAT_TEXT_MAP
      _inject_to_text_map(span, carrier)
    when Lightstep::Tracer::FORMAT_BINARY
      warn 'Binary inject format not yet implemented'
    else
      warn 'Unknown inject format'
    end
  end

  def join(operation_name, format, carrier)
    case format
    when Lightstep::Tracer::FORMAT_TEXT_MAP
      _join_from_text_map(operation_name, carrier)
    when Lightstep::Tracer::FORMAT_BINARY
      warn 'Binary join format not yet implemented'
      nil
    else
      warn 'Unknown join format'
      nil
    end
  end

  # ----------------------------------------------------------------------------
  # Implemenation specific
  # ----------------------------------------------------------------------------

  def initialize(options = {})
    @tracer_utils = Util.new
    @tracer_options = {}
    @tracer_enabled = true
    @tracer_guid = ''
    @tracer_start_time = @tracer_utils.now_micros
    @tracer_thrift_auth = nil
    @tracer_thrift_runtime = nil
    @tracer_transport = nil
    @tracer_report_start_time = 0
    @tracer_log_records = []
    @tracer_span_records = []
    @tracer_counters = {
      dropped_logs: 0,
      dropped_spans: 0
    }
    @tracer_last_flush_micros = 0
    @tracer_min_flush_period_micros = 0 # Initialized below by the default options
    @tracer_max_flush_period_micros = 0 # Initialized below by the default options

    @tracer_defaults = {
      collector_host: 'collector.lightstep.com',
      collector_port: 443,
      collector_encryption: 'tls',
      transport: 'http_json',
      max_log_records: 1000,
      max_span_records: 1000,
      min_reporting_period_secs: 1.5,
      max_reporting_period_secs: 30.0,

      max_payload_depth: 10,

      # Internal debugging flag that enables additional logging and
      # tracer checks. Not intended to run in production as it may add
      # logging "noise" to the calling code.
      verbose: 0
    }

    # Modify some of the interdependent defaults based on what the user-specified
    unless options[:collector_secure].nil?
      @tracer_defaults[:collector_port] = options[:collector_secure] ? 443 : 80
    end

    # Set the options, merged with the defaults
    set_options(@tracer_defaults.merge(options))

    @tracer_transport = if @tracer_options[:transport] == 'nil'
                          TransportNil.new
                        elsif @tracer_options[:transport] == 'callback'
                          TransportCallback.new
                        else
                          TransportHTTPJSON.new
                        end

    # Note: the GUID is not generated until the library is initialized
    # as it depends on the access token
    @tracer_start_time = @tracer_utils.now_micros
    @tracer_report_start_time = @tracer_start_time
    @tracer_last_flush_micros = @tracer_start_time

    # At exit, flush this objects data to the transport and close the transport
    # (which in turn will send the flushed data over the network).
    at_exit do
      flush
      @tracer_transport.close(false)
    end
  end

  def set_options(options)
    @tracer_options.merge!(options)

    # Deferred group name / access token initialization is supported (i.e.
    # it is possible to create logs/spans before setting this info).
    if !options[:access_token].nil? && !options[:component_name].nil?
      init_thrift_data_if_needed(options[:component_name], options[:access_token])
    end

    unless options[:min_reporting_period_secs].nil?
      @tracer_min_flush_period_micros = options[:min_reporting_period_secs] * 1E6
    end
    unless options[:max_reporting_period_secs]
      @tracer_max_flush_period_micros = options[:max_reporting_period_secs] * 1E6
    end

    # Coerce invalid options into stable values
    unless @tracer_options[:max_log_records] > 0
      @tracer_options[:max_log_records] = 1
      debug_record_error('Invalid value for max_log_records')
    end
    unless @tracer_options[:max_span_records] > 0
      @tracer_options[:max_span_records] = 1
      debug_record_error('Invalid value for max_span_records')
    end
  end

  def _inject_to_text_map(span, carrier)
    carrier[Lightstep::Tracer::CARRIER_TRACER_STATE_PREFIX + 'spanid'] = span.guid
    carrier[Lightstep::Tracer::CARRIER_TRACER_STATE_PREFIX + 'traceid'] = span.trace_guid unless span.trace_guid.nil?
    carrier[Lightstep::Tracer::CARRIER_TRACER_STATE_PREFIX + 'sampled'] = 'true'

    span.baggage.each do |key, value|
      carrier[Lightstep::Tracer::CARRIER_BAGGAGE_PREFIX + key] = value
    end
  end

  def _join_from_text_map(operation_name, carrier)
    span = ClientSpan.new(self)
    span.set_operation_name(operation_name)
    span.set_start_micros(@tracer_utils.now_micros)

    parent_guid = carrier[Lightstep::Tracer::CARRIER_TRACER_STATE_PREFIX + 'spanid']
    trace_guid = carrier[Lightstep::Tracer::CARRIER_TRACER_STATE_PREFIX + 'traceid']
    span.trace_guid = trace_guid
    span.set_tag(:parent_span_guid, parent_guid)

    carrier.each do |key, value|
      next unless key.start_with?(Lightstep::Tracer::CARRIER_BAGGAGE_PREFIX)
      plain_key = key.to_s[Lightstep::Tracer::CARRIER_BAGGAGE_PREFIX.length..key.to_s.length]
      span.set_baggage_item(plain_key, value)
    end
    span
  end

  def guid
    @tracer_guid
  end

  def access_token
    @tracer_options[:access_token]
  end

  # Reenables the tracer.
  def enable
    @tracer_enabled = true
  end

  # Disables the tracer.  If 'discardPending' is true, any queue tracing data is
  # discarded; otherwise, any queued data is flushed before the tracer is
  # disabled.
  def disable(discardPending = false)
    @tracer_enabled = false
    @tracer_transport.close(discardPending)
  end

  def flush
    _flush_worker
  end

  def _flush_worker
    return unless @tracer_enabled

    now = @tracer_utils.now_micros

    # The thrift configuration has not yet been set: allow logs and spans
    # to be buffered in this case, but flushes won't yet be possible.
    return if @tracer_thrift_runtime.nil?

    return if @tracer_log_records.empty? && @tracer_span_records.empty?

    @tracer_transport.ensure_connection(@tracer_options)

    # Ensure the log / span GUIDs are set correctly. This is covers a real
    # case: the runtime GUID cannot be generated until the access token
    # and group name are set (so that is the same GUID between script
    # invocations), but the library allows logs and spans to be buffered
    # prior to setting those values.  Any such 'early buffered' spans need
    # to have the GUID set; for simplicity, the code resets them all.
    @tracer_log_records.each do |log|
      log.runtime_guid = @tracer_guid
    end
    @tracer_span_records.each do |span|
      span.runtime_guid = @tracer_guid
    end

    # Convert the counters to thrift form
    thrift_counters = @tracer_counters.map do |key, value|
      NamedCounter.new(Name: key.to_s, Value: value.to_i)
    end
    report_request = ReportRequest.new(runtime: @tracer_thrift_runtime,
                                       oldest_micros: @tracer_report_start_time.to_i,
                                       youngest_micros: now.to_i,
                                       log_records: @tracer_log_records,
                                       span_records: @tracer_span_records,
                                       counters: thrift_counters)

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
    if !resp.nil? && resp.commands.class.name == 'Array'
      resp.commands.each do |cmd|
        disable if cmd.disable
      end
    end
  end

  # Internal use only.
  #
  # Generates a random ID (not a *true* UUID).
  def generate_uuid_string
    @tracer_utils.generate_guid
  end

  # Internal use only.
  def _finish_span(span)
    return unless @tracer_enabled

    span.set_end_micros(@tracer_utils.now_micros) if span.end_micros === 0
    full = push_with_max(@tracer_span_records, span.to_thrift, @tracer_options[:max_span_records])
    @tracer_counters[:dropped_spans] += 1 if full
    flush_if_needed
  end

  def raw_log_record(fields, payload)
    return unless @tracer_enabled

    fields[:runtime_guid] = @tracer_guid.to_s

    if fields[:timestamp_micros].nil?
      fields[:timestamp_micros] = @tracer_utils.now_micros.to_i
    end

    # TODO: data scrubbing and size limiting
    json = nil
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
    fields[:payload_json] = json if json.class.name == 'String'

    rec = LogRecord.new(fields)
    full = push_with_max(@tracer_log_records, rec, @tracer_options[:max_log_records])
    @tracer_counters[:dropped_logs] += 1 if full
  end

  protected

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

  def debug_record_error(e)
    if @tracer_options[:verbose] >= 2
      warn e.to_s
      exit(1)
    end
  end

  def flush_if_needed
    return unless @tracer_enabled

    now = @tracer_utils.now_micros
    delta = now - @tracer_last_flush_micros

    # Set a bound on maximum flush frequency
    return if delta < @tracer_min_flush_period_micros

    # Look for a trigger that a flush is warranted
    # Set a bound of minimum flush frequency
    if delta > @tracer_max_flush_period_micros ||
       @tracer_log_records.length >= @tracer_options[:max_log_records] / 2 ||
       @tracer_span_records.length >= @tracer_options[:max_span_records] / 2
      flush
    end
  end

  def init_thrift_data_if_needed(component_name, access_token)
    # Pre-conditions
    if access_token.class.name != 'String'
      warn 'access_token must be a string'
      exit(1)
    end
    if component_name.class.name != 'String'
      warn 'component_name must be a string'
      exit(1)
    end
    if access_token.empty?
      warn 'access_token must be non-zero in length'
      exit(1)
    end
    if component_name.empty?
      warn 'component_name must be non-zero in length'
      exit(1)
    end

    # Potentially redundant initialization info: only complain if
    # it is inconsistent.
    if !@tracer_thrift_auth.nil? || !@tracer_thrift_runtime.nil?
      if @tracer_thrift_auth.access_token != access_token
        warn 'access_token cannot be changed after it is set'
        exit(1)
        end
      if @tracer_thrift_runtime.group_name != component_name
        warn 'component name cannot be changed after it is set'
        exit(1)
      end
      return
    end

    # Tracer attributes
    runtime_attrs = {
      lightstep_tracer_platform: 'ruby',
      lightstep_tracer_version: Lightstep::Tracer::VERSION,
      ruby_version: RUBY_VERSION
    }

    # Generate the GUID on thrift initialization as the GUID should be
    # stable for a particular access token / component name combo.
    @tracer_guid = generate_uuid_string
    @tracer_thrift_auth = Auth.new(access_token: access_token.to_s)

    thrift_attrs = []
    runtime_attrs.each do |key, value|
      pair = KeyValue.new
      pair.Key = key.to_s
      pair.Value = value.to_s
      thrift_attrs.push(pair)
    end
    @tracer_thrift_runtime = Runtime.new('guid' => @tracer_guid.to_s,
                                         'start_micros' => @tracer_start_time.to_i,
                                         'group_name' => component_name.to_s,
                                         'attrs' => thrift_attrs)
  end
end
