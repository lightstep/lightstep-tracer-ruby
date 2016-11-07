module LightStep
  # SpanContext holds the data for a span that gets inherited to child spans
  class SpanContext
    attr_reader :id, :trace_id, :baggage

    def initialize(id:, trace_id:, baggage: {})
      @id = id.freeze
      @trace_id = trace_id.freeze
      @baggage = baggage.freeze
    end
  end
end
