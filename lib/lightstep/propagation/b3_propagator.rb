#frozen_string_literal: true

module LightStep
  module Propagation
    class B3Propagator < LightStepPropagator
      CARRIER_TRACER_STATE_PREFIX = 'x-b3-'
      CARRIER_SPAN_ID = 'x-b3-spanid'
      CARRIER_TRACE_ID = 'x-b3-traceid'
      CARRIER_SAMPLED = 'x-b3-sampled'
      TRUE_VALUES = %w[1 true].freeze

      private

      # propagate the full 128-bit trace id if the original id was 128-bit,
      # use the 64 bit id otherwise
      def trace_id_from_ctx(ctx)
        ctx.id_truncated? ? ctx.trace_id128 : ctx.trace_id64
      end

      def sampled_flag_from_ctx(ctx)
        ctx.sampled? ? '1' : '0'
      end

      def sampled_flag_from_carrier(carrier)
        TRUE_VALUES.include?(carrier[self.class::CARRIER_SAMPLED])
      end
    end
  end
end
