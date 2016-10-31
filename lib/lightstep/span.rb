# TODO(ngauthier@gmail.com) Separate Span and SpanContext under a getter according
# to the spec. Baggage moves to span context.
module LightStep
  # Span represents an OpenTracer Span
  #
  # See http://www.opentracing.io for more information.
  class Span
    # UnsupportedValueTypeError is raised when a tag value is not a supported type
    class UnsupportedValueTypeError < LightStep::Error; end

    # The guid of the span
    attr_reader :guid
    # Tags on the span
    attr_reader :tags
    # The baggage attached to this span
    attr_reader :baggage
    # The {Tracer} that created this span
    attr_reader :tracer

    # The guid of the current trace
    attr_accessor :trace_guid
    # The operation name
    attr_accessor :operation_name
    # Start time of the span in microseconds
    attr_accessor :start_micros
    # End time of the span in microseconds
    attr_accessor :end_micros

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
      child_of_guid: nil,
      trace_guid:,
      start_micros:,
      tags: nil
    )
      @tags = Hash(tags)
      @baggage = {}

      @tracer = tracer
      @guid = tracer.generate_guid
      self.operation_name = operation_name
      self.start_micros = start_micros
      self.trace_guid = trace_guid
      set_tag(:parent_span_guid, child_of_guid) if !child_of_guid.nil?
    end

    # Set a tag value on this span
    # @param key [String] the key of the tag
    # @param value [String, Numeric, Boolean] the value of the tag
    def set_tag(key, value)
      case value
      when String, Fixnum, TrueClass, FalseClass
        @tags[key] = value
      else
       raise UnsupportedValueTypeError,
         "Value must be a string, number, or boolean: "+
         "#{value.inspect} is a #{value.class.name}"
      end
      self
    end

    # TODO(ngauthier@gmail.com) baggage keys have a restricted format according
    # to the spec: http://opentracing.io/documentation/pages/spec#baggage-vs-span-tags

    # Set a baggage item on the span
    # @param key [String] the key of the baggage item
    # @param value [String] the value of the baggage item
    def set_baggage_item(key, value)
      @baggage[key] = value
      self
    end

    # Get a baggage item
    # @param key [String] the key of the baggage item
    # @return Value of the baggage item
    def get_baggage_item(key)
      @baggage[key]
    end

    # Log an event
    # @deprecated Use {#log} instead
    # @param event [String] the name of the event to log
    # @param payload [Hash] the payload of the log message
    def log_event(event, payload = nil)
      log(event: event.to_s, payload: payload)
    end

    # Add a log entry to this span
    # @param fields [Hash] fields to log.
    def log(fields)
      record = { span_guid: @guid }

      record[:stable_name] = fields[:event].to_s unless fields[:event].nil?
      unless fields[:timestamp].nil?
        record[:timestamp_micros] = (fields[:timestamp] * 1000).to_i
      end
      @tracer.raw_log_record(record, fields[:payload])
    end

    # Finish the {Span}
    # @param end_time [Time] custom end time, if not now
    def finish(end_time: Time.now)
      @tracer._finish_span(self, end_time: end_time)
      self
    end

    # Hash representation of a span
    def to_h
      {
        "runtime_guid" => tracer.guid,
        "span_guid" => guid,
        "trace_guid" => trace_guid,
        "span_name" => operation_name,
        "attributes" => @tags.map {|key, value|
          {"Key" => key.to_s, "Value" => value}
        },
        "oldest_micros" => start_micros,
        "youngest_micros" => end_micros,
        "error_flag" => false
      }
    end
  end
end
