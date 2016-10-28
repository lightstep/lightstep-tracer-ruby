# TODO(ngauthier@gmail.com) Separate Span and SpanContext under a getter according
# to the spec. Baggage moves to span context.
module LightStep
  class Span
    # ----------------------------------------------------------------------------
    #  OpenTracing API
    # ----------------------------------------------------------------------------

    class UnsupportedValueTypeError < LightStep::Error; end

    attr_reader :tracer

    # TODO(ngauthier@gmail.com) validate value is string, bool, or number and
    # remove value.to_s from all calling code
    def set_tag(key, value)
      case value
      when String, Fixnum, TrueClass, FalseClass
        @tags[key] = value
      else
       raise UnsupportedValueTypeError,
         "Value must be a string, number, or boolean: #{value.inspect} is a #{value.class.name}"
      end
      self
    end

    def set_baggage_item(key, value)
      @baggage[key] = value
      self
    end

    def get_baggage_item(key)
      @baggage[key]
    end

    # TODO(ngauthier@gmail.com) remove, since it's deprecated
    def log_event(event, payload = nil)
      log(event: event.to_s, payload: payload)
    end

    def log(fields)
      record = { span_guid: @guid }

      record[:stable_name] = fields[:event].to_s unless fields[:event].nil?
      unless fields[:timestamp].nil?
        record[:timestamp_micros] = (fields[:timestamp] * 1000).to_i
      end
      @tracer.raw_log_record(record, fields[:payload])
    end

    def finish(fields = nil)
      unless fields.nil?
        self.end_micros = fields[:endTime] * 1000 unless fields[:endTime].nil?
      end
      @tracer._finish_span(self)
      self
    end

    # ----------------------------------------------------------------------------
    # Implemenation specific
    # ----------------------------------------------------------------------------

    def initialize(tracer)
      @tags = {}
      @baggage = {}

      @tracer = tracer
      @guid = tracer.generate_guid
    end

    attr_reader :guid, :tags, :baggage
    attr_accessor :trace_guid

    def finalize
      if @end_micros == 0
        # TODO: Notify about that finish() was never called for this span
        finish
      end
    end

    attr_writer :start_micros
    def start_micros
      @start_micros ||= 0
    end

    attr_writer :end_micros
    def end_micros
      @end_micros ||= 0
    end

    attr_writer :operation_name
    def operation_name
      @operation_name ||= ''
    end

    def parent_guid
      @tags[:parent_span_guid]
    end

    def set_parent(span)
      set_tag(:parent_span_guid, span.guid)
      @trace_guid = span.trace_guid
      self
    end

    def to_h
      attributes = @tags.map do |key, value|
        {"Key" => key.to_s, "Value" => value}
      end

      rec = {
        "runtime_guid" => tracer.guid,
        "span_guid" => guid,
        "trace_guid" => trace_guid,
        "span_name" => operation_name,
        "attributes" => attributes,
        "oldest_micros" => start_micros,
        "youngest_micros" => end_micros,
        "error_flag" => false
      }
    end
  end
end
