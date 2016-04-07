require_relative './util'
require_relative '../thrift/types'

class ClientSpan

    attr_reader :tracer, :guid, :operation, :tags, :baggage, :start_micros, :end_micros, :error_flag, :join_ids

    def initialize(tracer)
        @guid = ""
        @operation = ""
        @tags = {}
        @baggage = {}
        @start_micros = 0
        @end_micros = 0
        @error_flag = false
        @join_ids = {}

        @tracer = tracer
        @guid = tracer.generate_uuid_string
    end

    def finalize
        if @end_micros == 0
            self.warnf("finish() never closed on span (operaton='%s')", @operation, @join_ids)
            self.finish
        end
    end

    def tracer
        @tracer
    end

    def guid
        @guid
    end

    def set_start_micros(start)
        @start_micros = start
       self
    end

    def set_end_micros(start)
        @end_micros = start
        self
    end

    def finish
        @tracer._finish_span(self)
    end

    def set_operation_name(name)
        @operation = name
        self
    end

    def set_tag(key, value)
        @tags[key] = value
        self
    end

    def set_baggage_item(key, value)
        @baggage[key] = value
        self
    end

    def get_baggage_item(key)
        @baggage[key]
    end

    def set_parent(span)
        # Inherit any join IDs from the parent that have not been explicitly
        # set on the child
        span.join_ids.each do |key, value|
            unless(@join_ids.has_key?(key))
                @join_ids[key] = value
            end
        end

        self.set_tag(:parent_span_guid, span.guid)
        self.set_tag('join:trace_id', span.tags['join:trace_id'])
        self
    end

    def log_event(event, payload = nil)
        self.log( { 'event' => event.to_s, 'payload' => payload } )
    end

    def log(fields)
          record = {:span_guid => @guid.to_s}
        payload = nil

        unless(fields[:event].nil?)
            record[:stable_name] = fields[:event].to_s
        end

        unless(fields[:timestamp].nil?)
            record[:timestamp_micros] = (fields[:timestamp] * 1000).to_i
        end
        @tracer.raw_log_record(record, fields[:payload])
    end

    def to_thrift
        # Coerce all the types to strings to ensure there are no encoding/decoding
        # issues
        join_ids = []
        @join_ids.each do |key, value|
            join_ids << TraceJoinId.new({:TraceKey => key.to_s, :Value => value.to_s})
        end

        attributes = Array.new
        @tags.each do |key, value|
            attributes << KeyValue.new({ :Key => key.to_s, :Value => value.to_s })
        end

        rec = SpanRecord.new({
            :runtime_guid => @tracer.guid().to_s,
            :span_guid => @guid.to_s,
            :span_name => @operation.to_s,
            :attributes => attributes,
            :oldest_micros => @start_micros.to_i,
            :youngest_micros => @end_micros.to_i,
            :join_ids => join_ids,
            :error_flag => @errorFlag
        })
    end
end
