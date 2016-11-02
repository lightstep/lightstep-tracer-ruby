# Things that will be copied to report:
# * min/max span records
# * min/max reporting period
#
# Things that move to report:
# * flushing (finish span just delegates to the reporter)
# * report runtime data
# * report timings
# * at_exit closes the reporter
# * flush_worker stuff

module LightStep
  # Reporter builds up reports of spans and flushes them to a transport
  class Reporter
    attr_accessor :max_span_records

    def initialize(max_span_records:, transport:, guid:, component_name:)
      @max_span_records = max_span_records
      @span_records = Concurrent::Array.new
      @dropped_spans = Concurrent::AtomicFixnum.new
      @dropped_span_logs = Concurrent::AtomicFixnum.new
      @transport = transport

      start_time = LightStep.micros(Time.now)
      @guid = LightStep.guid
      @report_start_time = start_time
      @last_flush_micros = start_time

      @runtime = {
        guid: guid,
        start_micros: start_time,
        group_name: component_name,
        attrs: [
          {Key: "lightstep.tracer_platform",         Value: "ruby"},
          {Key: "lightstep.tracer_version",          Value: LightStep::VERSION},
          {Key: "lightstep.tracer_platform_version", Value: RUBY_VERSION}
        ]
      }.freeze

      # At exit, flush this objects data to the transport and close the transport
      # (which in turn will send the flushed data over the network).
      at_exit do
        flush
        @transport.close
      end
    end

    def flush
      return if @span_records.empty?

      now = LightStep.micros(Time.now)

      span_records = @span_records.slice!(0, @span_records.length)
      dropped_spans = 0
      @dropped_spans.update{|old| dropped_spans = old; 0 }

      old_dropped_span_logs = 0
      @dropped_span_logs.update{|old| old_dropped_span_logs = old; 0 }
      dropped_logs = old_dropped_span_logs
      dropped_logs = span_records.reduce(dropped_logs) do |memo, span|
        memo += span.delete :dropped_logs
      end

      report_request = {
        runtime: @runtime,
        oldest_micros: @report_start_time,
        youngest_micros: now,
        span_records: span_records,
        counters: [
            {Name: "dropped_logs",  Value: dropped_logs},
            {Name: "dropped_spans", Value: dropped_spans},
        ]
      }

      @last_flush_micros = now
      @report_start_time = now

      begin
        @transport.report(report_request)
      rescue LightStep::Transport::HTTPJSON::QueueFullError
        # If the queue is full, add the previous dropped logs to the logs
        # that were going to get reported, as well as the previous dropped
        # spans and spans that would have been recorded
        @dropped_spans.increment(dropped_spans + span_records.length)
        @dropped_span_logs.increment(old_dropped_span_logs)
      end
    end

    def add_span(span)
      @span_records.push(span.to_h)
      if @span_records.size > max_span_records
        @span_records.shift
        @dropped_spans.increment
        @dropped_span_logs.increment(span.logs_count + span.dropped_logs_count)
      end
      flush_if_needed
    end

    def clear
      @transport.clear
    end

    private
    MIN_PERIOD_SECS = 1.5
    MAX_PERIOD_SECS = 30.0
    MIN_PERIOD_MICROS = MIN_PERIOD_SECS * 1E6
    MAX_PERIOD_MICROS = MAX_PERIOD_SECS * 1E6

    def flush_if_needed
      delta = LightStep.micros(Time.now) - @last_flush_micros
      return if delta < MIN_PERIOD_MICROS

      if delta > MAX_PERIOD_MICROS || @span_records.size >= max_span_records / 2
        flush
      end
    end
  end
end
