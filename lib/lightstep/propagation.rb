#frozen_string_literal: true

require 'lightstep/propagation/lightstep_propagator'
require 'lightstep/propagation/b3_propagator'

module LightStep
  module Propagation
    PROPAGATOR_MAP = {
      lightstep: LightStepPropagator,
      b3: B3Propagator
    }

    class << self
      # Constructs a propagator instance from the given propagator name. If the
      # name is unknown returns the LightStepPropagator as a default
      #
      # @param [Symbol, String] propagator_name One of :lightstep or :b3
      # @return [Propagator]
      def [](propagator_name)
        klass = PROPAGATOR_MAP[propagator_name.to_sym] || LightStepPropagator
        klass.new
      end
    end
  end
end
