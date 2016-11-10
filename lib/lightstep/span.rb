require 'concurrent'
require 'lightstep/span_context'

module LightStep
  # Span represents an OpenTracer Span
  #
  # See http://www.opentracing.io for more information.
  class Span
    # Part of the OpenTracing API
    attr_writer :operation_name

    # Internal use only
    # @private
    attr_reader :start_micros, :end_micros, :baggage, :tags, :operation_name, :span_context

    # Creates a new {Span}
    #
    # @param tracer [Tracer] the tracer that created this span
    # @param operation_name [String] the operation name of this span
    # @param child_of_guid [String] the guid of the span this span is a child of
    # @param trace_guid [String] the guid of this span's trace
    # @param start_micros [Numeric] start time of the span in microseconds
    # @return [Span] a new Span
    def initialize(
      tracer:,
      operation_name:,
      child_of_id: nil,
      trace_id:,
      start_micros:,
      tags: nil,
      max_log_records:
    )
      @tags = Concurrent::Hash.new
      @tags.update(tags) unless tags.nil?
      @log_records = Concurrent::Array.new
      @dropped_logs = Concurrent::AtomicFixnum.new
      @max_log_records = max_log_records

      @tracer = tracer
      self.operation_name = operation_name
      self.start_micros = start_micros
      @span_context = SpanContext.new(id: LightStep.guid, trace_id: trace_id)
      set_tag(:parent_span_guid, child_of_id) if !child_of_id.nil?
    end

    # Set a tag value on this span
    # @param key [String] the key of the tag
    # @param value [String, Numeric, Boolean] the value of the tag. If it's not
    # a String, Numeric, or Boolean it will be encoded with to_s
    def set_tag(key, value)
      case value
      when String, Fixnum, TrueClass, FalseClass
        tags[key] = value
      else
        tags[key] = value.to_s
      end
      self
    end

    # TODO(ngauthier@gmail.com) baggage keys have a restricted format according
    # to the spec: http://opentracing.io/documentation/pages/spec#baggage-vs-span-tags

    # Set a baggage item on the span
    # @param key [String] the key of the baggage item
    # @param value [String] the value of the baggage item
    def set_baggage_item(key, value)
      @span_context = SpanContext.new(
        id: span_context.id,
        trace_id: span_context.trace_id,
        baggage: span_context.baggage.merge({key => value})
      )
      self
    end

    # Set all baggage at once. This will reset the baggage to the given param.
    # @param baggage [Hash] new baggage for the span
    def set_baggage(baggage = {})
      @span_context = SpanContext.new(
        id: span_context.id,
        trace_id: span_context.trace_id,
        baggage: baggage
      )
    end

    # Get a baggage item
    # @param key [String] the key of the baggage item
    # @return Value of the baggage item
    def get_baggage_item(key)
      span_context.baggage[key]
    end

    # Add a log entry to this span
    # @param event [String] event name for the log
    # @param timestamp [Time] time of the log
    # @param fields [Hash] Additional information to log
    def log(event: nil, timestamp: Time.now, **fields)
      return unless tracer.enabled?

      record = {
        runtime_guid: tracer.guid,
        timestamp_micros: LightStep.micros(timestamp)
      }
      record[:stable_name] = event.to_s if !event.nil?

      begin
        record[:payload_json] = JSON.generate(fields, max_nesting: 8)
      rescue
        # TODO: failure to encode a payload as JSON should be recorded in the
        # internal library logs, with catioun not flooding the internal logs.
      end

      log_records.push(record)
      if log_records.size > @max_log_records
        log_records.shift
        dropped_logs.increment
      end
    end

    # Finish the {Span}
    # @param end_time [Time] custom end time, if not now
    def finish(end_time: Time.now)
      if end_micros.nil?
        self.end_micros = LightStep.micros(end_time)
      end
      tracer.finish_span(self)
      self
    end

    # Hash representation of a span
    def to_h
      {
        runtime_guid: tracer.guid,
        span_guid: span_context.id,
        trace_guid: span_context.trace_id,
        span_name: operation_name,
        attributes: tags.map {|key, value|
          {Key: key.to_s, Value: value}
        },
        oldest_micros: start_micros,
        youngest_micros: end_micros,
        error_flag: false,
        dropped_logs: dropped_logs_count,
        log_records: log_records
      }
    end

    # Internal use only
    # @private
    def dropped_logs_count
      dropped_logs.value
    end

    # Internal use only
    # @private
    def logs_count
      log_records.size
    end

    private

    attr_reader :tracer, :dropped_logs, :log_records
    attr_writer :start_micros, :end_micros
  end
end
