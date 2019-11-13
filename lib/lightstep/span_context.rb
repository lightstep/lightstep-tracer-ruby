#frozen_string_literal: true

module LightStep
  # SpanContext holds the data for a span that gets inherited to child spans
  class SpanContext
    attr_reader :id, :trace_id, :trace_id_upper64, :sampled, :baggage
    alias_method :trace_id64, :trace_id
    alias_method :sampled?, :sampled

    ZERO_PADDING = '0' * 16

    def initialize(id:, trace_id:, trace_id_upper64: nil, sampled: true, baggage: {})
      @id = id.freeze
      @trace_id = truncate_id(trace_id).freeze
      @trace_id_upper64 = trace_id_upper64 || extended_bits(trace_id).freeze
      @sampled = sampled
      @baggage = baggage.freeze
    end

    # Lazily initializes and returns a 128-bit representation of a 64-bit trace id
    def trace_id128
      @trace_id128 ||= "#{trace_id_upper64 || ZERO_PADDING}#{trace_id}"
    end

    # Returns true if the original trace_id was 128 bits
    def id_truncated?
      !@trace_id_upper64.nil?
    end

    private

    # Truncates an id to 64 bits
    def truncate_id(id)
      return id unless id && id.size == 32
      id[16..-1]
    end

    # Returns the most significant 64 bits of a 128 bit id or nil if the id
    # is 64 bits
    def extended_bits(id)
      return unless id && id.size == 32
      id[0...16]
    end
  end
end
