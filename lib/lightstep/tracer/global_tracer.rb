require 'singleton'

module LightStep
  class GlobalTracer < Tracer
    def initialize
    end
    
    include Singleton

    def configure(opts = nil)
      raise ConfigurationError, "Already configured" if configured
      self.configured = true
      super
    end

    private
    attr_accessor :configured
  end
end
