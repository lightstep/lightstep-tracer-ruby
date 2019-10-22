#frozen_string_literal: true

module LightStep
  # SpanContext holds the data for a span that gets inherited to child spans
  class SpanContext
    attr_reader :id, :trace_id, :trace_id16, :baggage

    ZERO_PADDING = '0' * 16

    def initialize(id:, trace_id:, baggage: {})
      @id = id.freeze
      @trace_id16 = pad_id(trace_id).freeze
      @trace_id = truncate_id(trace_id).freeze
      @baggage = baggage.freeze
    end

    private

    def truncate_id(id)
      return id unless id && id.size == 32
      id[16..-1]
    end

    def pad_id(id)
      return id unless id && id.size == 16
      "#{ZERO_PADDING}#{id}"
    end
  end
end
