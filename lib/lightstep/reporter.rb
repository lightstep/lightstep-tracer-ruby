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
        @span_records.shift
        @dropped_spans.increment
      end
    end

    def clear
      reset_on_fork

      span_records = @span_records.slice!(0, @span_records.length)
      @dropped_spans.increment(span_records.size)
    end

    def flush
      reset_on_fork

      return if @span_records.empty?

      now = LightStep.micros(Time.now)

      span_records = @span_records.slice!(0, @span_records.length)
      dropped_spans = 0
      @dropped_spans.update do |old|
        dropped_spans = old
        0
      end

      report_request = {
        runtime: @runtime,
        oldest_micros: @report_start_time,
        youngest_micros: now,
        span_records: span_records,
        internal_metrics: {
          counts: [{
            name: 'spans.dropped',
            int64_value: dropped_spans
          }]
        }
      }

      @report_start_time = now

      begin
        @transport.report(report_request)
      rescue StandardError => e
        LightStep.logger.error "LightStep error reporting to collector: #{e.message}"
        # an error occurs, add the previous dropped_spans and count of spans
        # that would have been recorded
        @dropped_spans.increment(dropped_spans + span_records.length)
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
        rescue StandardError => e
          LightStep.logger.error "LightStep failed to report spans: #{e.message}"
        end
      end
    end
  end
end
