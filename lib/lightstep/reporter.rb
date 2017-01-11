require 'lightstep/version'

module LightStep
  # Reporter builds up reports of spans and flushes them to a transport
  class Reporter
    DEFAULT_PERIOD_SECONDS = 3.0
    attr_accessor :max_span_records
    attr_accessor :period

    def initialize(max_span_records:, transport:, guid:, component_name:, tags: {})
      @max_span_records = max_span_records
      @span_records = Concurrent::Array.new
      @dropped_spans = Concurrent::AtomicFixnum.new
      @dropped_span_logs = Concurrent::AtomicFixnum.new
      @transport = transport
      @period = DEFAULT_PERIOD_SECONDS

      start_time = LightStep.micros(Time.now)
      @report_start_time = start_time

      @runtime = {
        guid: guid,
        start_micros: start_time,
        group_name: component_name,
        attrs: [
          {Key: "lightstep.tracer_platform",         Value: "ruby"},
          {Key: "lightstep.tracer_version",          Value: LightStep::VERSION},
          {Key: "lightstep.tracer_platform_version", Value: RUBY_VERSION}
        ] + tags.map{|k,v| {Key: k.to_s, Value: v.to_s}}
      }.freeze

      reset_on_fork
    end

    def add_span(span)
      reset_on_fork

      @span_records.push(span.to_h)
      if @span_records.size > max_span_records
        dropped = @span_records.shift
        @dropped_spans.increment
        @dropped_span_logs.increment(dropped[:log_records].size + dropped[:dropped_logs])
      end
    end

    def clear
      reset_on_fork

      span_records = @span_records.slice!(0, @span_records.length)
      @dropped_spans.increment(span_records.size)
      @dropped_span_logs.increment(
        span_records.reduce(0) {|memo, span|
          memo + span[:log_records].size + span[:dropped_logs]
        }
      )
    end

    def flush
      reset_on_fork

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
        internal_metrics: {
	  counts: [
	    {name: "spans.dropped", int64_value: dropped_spans},
	  ]
        }
      }

      @report_start_time = now

      begin
        @transport.report(report_request)
      rescue
        # an error occurs, add the previous dropped logs to the logs
        # that were going to get reported, as well as the previous dropped
        # spans and spans that would have been recorded
        @dropped_spans.increment(dropped_spans + span_records.length)
        @dropped_span_logs.increment(old_dropped_span_logs)
      end
    end

    private

    # When the process forks, reset the child. All data that was copied will be handled
    # by the parent. Also, restart the thread since forking killed it
    def reset_on_fork
      if @pid != $$
        @pid = $$
        @span_records.clear
        @dropped_spans.value = 0
        @dropped_span_logs.value = 0
        report_spans
      end
    end

    def report_spans
      return if @period <= 0
      Thread.new do
        begin
          loop do
            sleep(@period)
            flush
          end
        rescue => ex
          # TODO: internally log the exception
        end
      end
    end
  end
end
