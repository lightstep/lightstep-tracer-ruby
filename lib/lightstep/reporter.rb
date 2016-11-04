require 'concurrent/channel'

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
      @report_start_time = start_time

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

      reset_on_fork

      at_exit do
        @quit_signal << true
        @thread.join
      end
    end

    def add_span(span)
      reset_on_fork

      @span_records.push(span.to_h)
      if @span_records.size > max_span_records
        dropped = @span_records.shift
        @dropped_spans.increment
        @dropped_span_logs.increment(dropped[:log_records].size + dropped[:dropped_logs])
      end

      @span_signal << true
    end

    def clear
      span_records = @span_records.slice!(0, @span_records.length)
      @dropped_spans.increment(span_records.size)
      @dropped_span_logs.increment(
        span_records.reduce(0) {|memo, span|
          memo + span[:log_records].size + span[:dropped_logs]
        }
      )
    end

    def flush
      @flush_signal << true
      ~@flush_response_signal
    end

    private
    MIN_PERIOD_SECS = 1.5
    MAX_PERIOD_SECS = 30.0

    # When the process forks, reset the child. All data that was copied will be handled
    # by the parent. Also, restart the thread since forking killed it
    def reset_on_fork
      if @pid != $$
        @pid = $$
        @span_signal = Concurrent::Channel.new(buffer: :dropping, capacity: 1)
        @quit_signal = Concurrent::Channel.new(buffer: :dropping, capacity: 1)
        @flush_signal = Concurrent::Channel.new
        @flush_response_signal = Concurrent::Channel.new
        @span_records.clear
        @dropped_spans.value = 0
        @dropped_span_logs.value = 0
        report_spans
      end
    end

    def perform_flush
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
        counters: [
          {Name: "dropped_logs",  Value: dropped_logs},
          {Name: "dropped_spans", Value: dropped_spans},
        ]
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

    def report_spans
      @thread = Thread.new do
        begin
          loop do
            min_reached = false
            max_reached = false
            min_timer = Concurrent::Channel.timer(MIN_PERIOD_SECS)
            max_timer = Concurrent::Channel.timer(MAX_PERIOD_SECS)
            loop do
              Concurrent::Channel.select do |s|
                s.take(@span_signal) do
                  # we'll check span count below
                end
                s.take(min_timer) do
                  min_reached = true
                end
                s.take(max_timer) do
                  max_reached = true
                end
                s.take(@quit_signal) do
                  perform_flush
                  Thread.exit
                end
                s.take(@flush_signal) do
                  perform_flush
                  @flush_response_signal << true
                end
              end
              if max_reached || (min_reached && @span_records.size >= max_span_records / 2)
                perform_flush
              end
            end
          end
        rescue => ex
          # TODO: internally log the exception
        end
      end
    end
  end
end
