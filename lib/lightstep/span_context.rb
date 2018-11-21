module LightStep
  # SpanContext holds the data for a span that gets inherited to child spans
  class SpanContext
    attr_reader :id, :trace_id, :baggage, :trace_state

    def initialize(id:, trace_id:, baggage: {}, trace_state: [])
      @id = id.freeze
      @trace_id = trace_id.freeze
      @baggage = baggage.freeze
      @trace_state = trace_state.freeze
    end
  end
end
