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
    attr_reader :start_micros, :end_micros, :tags, :operation_name, :span_context

    # Creates a new {Span}
    #
    # @param tracer [Tracer] the tracer that created this span
    # @param operation_name [String] the operation name of this span. If it's
    #        not a String it will be encoded with to_s.
    # @param child_of [SpanContext] the parent SpanContext (per child_of)
    # @param start_micros [Numeric] start time of the span in microseconds
    # @param tags [Hash] initial key:value tags (per set_tag) for the Span
    # @param max_log_records [Numeric] maximum allowable number of log records
    #        for the Span
    # @return [Span] a started Span
    def initialize(
      tracer:,
      operation_name:,
      child_of: nil,
      start_micros:,
      tags: nil,
      max_log_records:
    )
      child_of = child_of.span_context if (Span === child_of)
      @tags = Concurrent::Hash.new
      @tags.update(tags) unless tags.nil?
      @log_records = Concurrent::Array.new
      @dropped_logs = Concurrent::AtomicFixnum.new
      @max_log_records = max_log_records

      @tracer = tracer
      self.operation_name = operation_name.to_s
      self.start_micros = start_micros

      trace_id = (SpanContext === child_of ? child_of.trace_id : LightStep.guid)
      @span_context = SpanContext.new(id: LightStep.guid, trace_id: trace_id)

      if SpanContext === child_of
        set_baggage(child_of.baggage)
        set_tag(:parent_span_guid, child_of.id)
      end
    end

    # Set a tag value on this span
    # @param key [String] the key of the tag
    # @param value [String] the value of the tag. If it's not a String
    # it will be encoded with to_s
    def set_tag(key, value)
      tags[key] = value.to_s
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

      fields = {} if fields.nil?
      unless event.nil?
	fields[:event] = event.to_s
      end
      record = {
        timestamp_micros: LightStep.micros(timestamp),
        fields: fields.to_a.map {|key, value|
          {Key: key.to_s, Value: value.to_s}
        },
      }

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
