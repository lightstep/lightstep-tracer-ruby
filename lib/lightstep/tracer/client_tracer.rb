require 'securerandom'
require 'json'

require_relative './client_span'
require_relative './no_op_span'
require_relative './util'
require_relative './transports/transport_http_json'
require_relative './thrift/types'

LIGHTSTEP_VERSION = '0.1.0'

# ============================================================
 # Main implementation of the Tracer interface
# =============================================================

class ClientTracer

  def initialize(options = {})

    @tracer_utils = Util.new
    @tracer_options = {}
    @tracer_enabled = true
    @tracer_debug = false
    @tracer_guid = ""
    @tracer_start_time = @tracer_utils.now_micros
    @tracer_thrift_auth = nil
    @tracer_thrift_runtime = nil
    @tracer_transport = nil
    @tracer_report_start_time = 0
    @tracer_log_records = Array.new
    @tracer_span_records = Array.new
    @tracer_counters = {:dropped_logs => 0, :dropped_counters => 0}
    @tracer_last_flush_micros = 0
    @tracer_min_flush_period_micros = 0
    @tracer_max_flush_period_micros = 0

    @tracer_defaults = {
        :collector_host => 'collector.lightstep.com',
        :collector_port => 443,
        :collector_encryption => 'tls',
        :transport => 'http_json',
        :max_log_records => 1000,
        :max_span_records => 1000,
        :min_reporting_period_secs => 0.1,
        :max_reporting_period_secs => 5.0,

        :max_payload_depth => 10,

        # Internal debugging flag that enables additional logging and
        # tracer checks. Not intended to run in production as it may add
        # logging "noise" to the calling code.
        :verbose => 0,

        # Flag intended solely to unit testing convenience
        :debug_disable_flush => false
    }

    # Modify some of the interdependent defaults based on what the user-specified
    unless (options[:collector_secure].nil?)
      @tracer_defaults[:collector_port] = options[:collector_secure] ? 443 : 80
    end

    # UDP has significantly lower size contraints
    if (!options[:transport].nil? && options[:transport] == 'udp')
      @tracer_defaults[:max_log_records] = 16
      @tracer_defaults[:max_span_records] = 16
    end

    # Set the options, merged with the defaults
    self.set_option(@tracer_defaults.merge(options))

    if (@tracer_options[:transport] == 'udp')
      @tracer_transport = TransportUDP.new
    else
      @tracer_transport = TransportHTTPJSON.new
    end

    # Note: the GUID is not generated until the library is initialized
    # as it depends on the access token
    @tracer_start_time = @tracer_utils.now_micros
    @tracer_report_start_time = @tracer_start_time
    @tracer_last_flush_micros =@tracer_start_time

  end

  # def self.finalize(bar)
  #   puts "DESTROY OBJECT #{bar}"
  #   exit(0)
  # end

  def finalize
    self.flush
  end

  def set_option(options)

    @tracer_options.merge!(options)

    # Deferred group name / access token initialization is supported (i.e.
    # it is possible to create logs/spans before setting this info).
    if (!options[:access_token].nil? && !options[:component_name].nil?)
      self.init_thrift_data_if_needed(options[:component_name], options[:access_token])
    end

    unless (options[:min_reporting_period_secs].nil?)
      @tracer_min_flush_period_micros = options[:min_reporting_period_secs] * 1E6
    end
    unless (options[:max_reporting_period_secs])
      @tracer_max_flush_period_micros = options[:max_reporting_period_secs] * 1E6
    end

    @tracer_debug = (@tracer_options[:verbose] > 0)

    # Coerce invalid options into stable values
    unless (@tracer_options[:max_log_records] > 0)
      @tracer_options[:max_log_records] = 1
      self.debug_record_error('Invalid value for max_log_records')
    end
    unless (@tracer_options[:max_span_records] > 0)
      @tracer_options[:max_span_records] = 1
      self.debug_record_error('Invalid value for max_span_records')
    end
  end

  def guid
    return @tracer_guid
  end

  def disable
    self.discard
    @tracer_enabled = false
  end

  # ===========================================================
  # Internal use only.
  # Discard all currently buffered data.  Useful for unit testing.
  # ===========================================================
  def discard
    @tracer_log_records = {}
    @tracer_span_records = {}
  end

  def start_span(operation_name, fields = nil)
    unless (@tracer_enabled)
      return NoOpSpan.new
    end

    span = ClientSpan.new(self)
    span.set_operation_name(operation_name)
    span.set_start_micros(@tracer_utils.now_micros)
    span.set_tag('join:trace_id', self.generate_uuid_string)

    unless (fields.nil?)
      unless (fields[:parent].nil?)
        span.set_parent(fields[:parent])
      end
      unless (fields[:tags].nil?)
        span.set_tags(fields[:tags])
      end
      unless (fields[:startTime].nil?)
        span.set_start_micros(fields[:startTime] * 1000)
      end
    end
    return span
  end

  def flush
    unless (@tracer_enabled)
      return
    end

    now = @tracer_utils.now_micros

    # The thrift configuration has not yet been set: allow logs and spans
    # to be buffered in this case, but flushes won't yet be possible.
    if @tracer_thrift_runtime.nil?
      return
    end

    if (@tracer_log_records.length == 0 && @tracer_span_records.length == 0)
      return
    end

    # For unit testing
    if (@tracer_options[:debug_disable_flush])
      return
    end

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
    thrift_counters = []
    @tracer_counters.each do |key, value|
      thrift_counters.push(NamedCounter.new(
        :Name => key.to_s,
        :Value => value.to_i,
      ))
    end
    report_request = ReportRequest.new({:runtime => @tracer_thrift_runtime, :oldest_micros => @tracer_report_start_time.to_i, :youngest_micros => now.to_i, :log_records => @tracer_log_records, :span_records => @tracer_span_records, :counters => thrift_counters})

    @tracer_last_flush_micros = now

    resp = nil
    # try {
    #   # It *is* valid for the transport to return a null response in the
    #   # case of a low-overhead "fire and forget" report
    resp = @tracer_transport.flush_report(@tracer_thrift_auth, report_request)
    # } catch (\Exception $e) {
    #   # Exceptions *are* expected as connections can be broken, etc. when
    #   # reporting. Prevent reporting exceptions from interfering with the
    #   # client code.
    #   $this->debug_record_error($e);
    # end

    # ALWAYS reset the buffers and update the counters as the RPC response
    # is, by design, not waited for and not reliable.
    @tracer_report_start_time = now
    @tracer_log_records = Array.new
    @tracer_span_records = Array.new
    @tracer_counters.each do |key, value|
      value = 0
    end

    # Process server response commands
    if (!resp.nil? && resp.commands.class.name == 'Array')
      resp.commands.each do |cmd|
        if (cmd.disable)
          self.disable
        end
      end
    end
  end

    # Internal use only.
    #
    # Generates a random ID (not a *true* UUID).
    def generate_uuid_string
        return SecureRandom.hex(8)
    end

    # Internal use only.
    def _finish_span(span)
        unless (@tracer_enabled)
            return
        end
        span.set_end_micros(@tracer_utils.now_micros)
        full = self.push_with_max(@tracer_span_records, span.to_thrift, @tracer_options[:max_span_records])
        if full
            @tracer_counters[:dropped_spans] += 1
        end
        self.flush_if_needed
    end

  # =============================================================
   # For internal use only.
  # =============================================================
  def log(level, fmt, *args)
    # The $allArgs variable contains the $fmt string
    # args.shift
    # text = vsprintf(fmt, allArgs)
    text = args.join(',')

    self.raw_log_record({:level => level, :message => text}, args)

    self.flush_if_needed
    return text
  end

    # ==============================================================
    # Internal use only.
    # ==============================================================
    def raw_log_record(fields, payload_array)
        unless (@tracer_enabled)
          return
        end

        fields[:runtime_guid] = @tracer_guid.to_s

        if (fields[:timestamp_micros].nil?)
            fields[:timestamp_micros] = @tracer_utils.now_micros.to_i
        end

        # TODO: data scrubbing and size limiting
        if (!payload_array.nil? && payload_array.size > 0)
            json = JSON.generate(payload_array)
            if (json.class.name == 'String')
                fields[:payload_json] = json
            end
        end

        rec = LogRecord.new(fields)
        full = self.push_with_max(@tracer_log_records, rec, @tracer_options[:max_log_records])
        if full
            @tracer_counters[:dropped_logs] += 1
        end
    end

  protected

    def push_with_max(arr, item, max)
      unless (max > 0)
        max = 1
      end

      arr << item

      # Simplistic random discard
      count = arr.size
      if (count > max)
        i = @tracer_utils.randIntRange(0, max - 1)
        arr[i] = arr.pop
        return true
      else
        return false
      end
    end

    def debug_record_error(e)
      if (@tracer_debug)
        # error_log(e)
        puts e.to_s
        exit(1)
      end
    end

    # PHP does not have an event loop or timer threads. Instead manually check as
    # new data comes in by calling this method.
    def flush_if_needed
      unless (@tracer_enabled)
        return
      end

      now = @tracer_utils.now_micros
      delta = now - @tracer_last_flush_micros

      # Set a bound on maximum flush frequency
      if (delta < @tracer_min_flush_period_micros)
        return
      end

      # Set a bound of minimum flush frequency
      if (delta > @tracer_max_flush_period_micros)
        self.flush
        return
      end

      # Look for a trigger that a flush is warranted
      if (@tracer_log_records.length >= @tracer_options[:max_log_records])
        self.flush
        return
      end
      if (@tracer_span_records.length >= @tracer_options[:max_span_records])
        self.flush
        return
      end
    end

    def init_thrift_data_if_needed(component_name, access_token)

      # Pre-conditions
      if (access_token.class.name != 'String')
        puts 'access_token must be a string'
        exit(1)
      end
      if (component_name.class.name != 'String')
        puts 'component_name must be a string'
        exit(1)
      end
      unless (access_token.size > 0)
        puts 'access_token must be non-zero in length'
        exit(1)
      end
      unless (component_name.size > 0)
        puts 'component_name must be non-zero in length'
        exit(1)
      end

      # Potentially redundant initialization info: only complain if
      # it is inconsistent.
      if (!@tracer_thrift_auth.nil? || !@tracer_thrift_runtime.nil?)
        if (@tracer_thrift_auth.access_token != access_token)
          puts 'access_token cannot be changed after it is set'
          exit(1)
        end
        if (@tracer_thrift_runtime.group_name != component_name)
          puts 'component name cannot be changed after it is set'
          exit(1)
        end
        return
      end

      # Tracer attributes
      runtime_attrs = {
          :lightstep_tracer_platform => 'ruby',
          :lightstep_tracer_version => LIGHTSTEP_VERSION,
          :ruby_version => RUBY_VERSION
      }

      # Generate the GUID on thrift initialization as the GUID should be
      # stable for a particular access token / component name combo.
      @tracer_guid = self.generate_uuid_string()
      @tracer_thrift_auth = Auth.new({:access_token => access_token.to_s})

      thrift_attrs = []
      runtime_attrs.each do |key, value|
        pair = KeyValue.new
        pair.Key = key.to_s
        pair.Value = value.to_s
        thrift_attrs.push(pair)
      end
      @tracer_thrift_runtime = Runtime.new({
          'guid' => @tracer_guid.to_s,
          'start_micros' => @tracer_start_time.to_i,
          'group_name' => component_name.to_s,
          'attrs' => thrift_attrs
       })
    end
end
