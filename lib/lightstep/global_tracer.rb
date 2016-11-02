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
      raise ConfigurationError, 'Already configured' if configured
      self.configured = true
      super
    end

    private

    attr_accessor :configured
  end
end
