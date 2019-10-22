#frozen_string_literal: true

module LightStep
  module Propagation
    class B3Propagator < LightStepPropagator
      CARRIER_TRACER_STATE_PREFIX = 'x-b3-'
      CARRIER_SPAN_ID = 'x-b3-spanid'
      CARRIER_TRACE_ID = 'x-b3-traceid'
      CARRIER_SAMPLED = 'x-b3-sampled'

      private

      def trace_id_from_ctx(ctx)
        ctx.trace_id16
      end

      def sampled_flag_from_ctx(ctx)
        ctx.sampled? ? '1' : '0'
      end

      def sampled_flag_from_carrier(carrier)
        carrier[self.class::CARRIER_SAMPLED] == '1' ? true : false
      end
    end
  end
end
