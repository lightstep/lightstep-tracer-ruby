require 'lightstep/proto/collector_pb'

module LightStep
  class ReportRequest

   # @param [Object] runtime
   # @param [Numeric] oldest_micros
   # @param [Numeric] youngest_micros
   # @param [Object] span_records
   # @param [Integer] spans_dropped
   #
   # @return [ReportRequest] a new ReportRequest
     def initialize(runtime, oldest_micros, youngest_micros, span_records = [], spans_dropped = 0)
     @runtime = runtime
     @oldest_micros = oldest_micros
     @youngest_micros = youngest_micros
     @span_records = span_records
      @counts = [{
                  name: 'spans.dropped',
                  int64_value: spans_dropped
               }]
      end

    def to_proto(auth)
      report = Lightstep::Collector::ReportRequest.new
      puts "hiiiiii"
      puts report
      report.Auth = auth.to_proto()
      puts report
      puts "report:"
      puts report.Auth
    end
  end
end