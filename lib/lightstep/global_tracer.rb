require 'singleton'

module LightStep
  # GlobalTracer is a singleton version of the LightStep::Tracer.
  #
  # You should access it via `LightStep.instance`.
  class GlobalTracer < Tracer
    private
    def initialize
    end

    public
    include Singleton

    # Configure the GlobalTracer
    # See {LightStep::Tracer#initialize}
    def configure(**options)
      if configured
        LightStep.logger.warn "LIGHTSTEP WARNING: Already configured. Stack trace:\n\t#{caller.join("\n\t")}"
        return
      end

      self.configured = true
      super
    end

    private

    attr_accessor :configured
  end
end
