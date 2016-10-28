# TODO(ngauthier@gmail.com) Separate Span and SpanContext under a getter according
# to the spec. Baggage moves to span context.
module LightStep
  class Span
    class UnsupportedValueTypeError < LightStep::Error; end

    attr_reader :guid, :tags, :baggage, :tracer
    attr_accessor :trace_guid, :operation_name, :start_micros, :end_micros

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

    # TODO(ngauthier@gmail.com) []=
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

    def finish(end_time: Time.now)
      @tracer._finish_span(self, end_time: end_time)
      self
    end

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
