# TODO(ngauthier@gmail.com) Separate Span and SpanContext under a getter according
# to the spec. Baggage moves to span context.

module LightStep
  class Span
    # ----------------------------------------------------------------------------
    #  OpenTracing API
    # ----------------------------------------------------------------------------

    attr_reader :tracer

    # TODO(ngauthier@gmail.com) validate value is string, bool, or number and
    # remove value.to_s from all calling code
    def set_tag(key, value)
      @tags[key] = value
      self
    end

    # FIXME(ngauthier@gmail.com) accessor
    def set_baggage_item(key, value)
      @baggage[key] = value
      self
    end

    # FIXME(ngauthier@gmail.com) accessor
    # TODO(ngauthier@gmail.com) remove? Not in spec to get baggage.
    def get_baggage_item(key)
      @baggage[key]
    end

    # TODO(ngauthier@gmail.com) remove, since it's deprecated
    def log_event(event, payload = nil)
      log(event: event.to_s, payload: payload)
    end

    def log(fields)
      record = { span_guid: @guid.to_s }

      record[:stable_name] = fields[:event].to_s unless fields[:event].nil?
      unless fields[:timestamp].nil?
        record[:timestamp_micros] = (fields[:timestamp] * 1000).to_i
      end
      @tracer.raw_log_record(record, fields[:payload])
    end

    # FIXME(ngauthier@gmail.com) keyword arg?
    def finish(fields = nil)
      unless fields.nil?
        set_end_micros(fields[:endTime] * 1000) unless fields[:endTime].nil?
      end
      @tracer._finish_span(self)
      self
    end

    # ----------------------------------------------------------------------------
    # Implemenation specific
    # ----------------------------------------------------------------------------

    def initialize(tracer)
      @guid = ''
      @operation = ''
      @trace_guid = nil
      @tags = {}
      @baggage = {}
      @start_micros = 0
      @end_micros = 0
      @error_flag = false

      @tracer = tracer
      @guid = tracer.generate_guid
    end

    attr_reader :guid, :operation, :tags, :baggage, :start_micros, :end_micros, :error_flag
    attr_accessor :trace_guid

    def finalize
      if @end_micros == 0
        # TODO: Notify about that finish() was never called for this span
        finish
      end
    end

    # FIXME(ngauthier@gmail.com) writer
    def set_start_micros(start)
      @start_micros = start
      self
    end

    # FIXME(ngauthier@gmail.com) writer
    def set_end_micros(micros)
      @end_micros = micros
      self
    end

    # FIXME(ngauthier@gmail.com) writer
    def set_operation_name(name)
      @operation = name
      self
    end

    def parent_guid
      @tags[:parent_span_guid]
    end

    # FIXME(ngauthier@gmail.com) constant prefix
    # FIXME(ngauthier@gmail.com) safe url generation?
    # FIXME(ngauthier@gmail.com) getter
    def generate_trace_url
      "https://app.lightstep.com/#{@tracer.access_token}/trace?span_guid=#{@guid}&at_micros=#{start_micros}"
    end

    # FIXME(ngauthier@gmail.com) writer
    def set_parent(span)
      set_tag(:parent_span_guid, span.guid)
      @trace_guid = span.trace_guid
      self
    end

    # FIXME(ngauthier@gmail.com) to_h
    def to_thrift
      attributes = @tags.map do |key, value|
        {"Key" => key.to_s, "Value" => value.to_s}
      end

      rec = {
        "runtime_guid" => @tracer.guid.to_s,
        "span_guid" => @guid.to_s,
        "trace_guid" => @trace_guid.to_s,
        "span_name" => @operation.to_s,
        "attributes" => attributes,
        "oldest_micros" => @start_micros.to_i,
        "youngest_micros" => @end_micros.to_i,
        "error_flag" => @error_flag
      }
    end
  end
end
