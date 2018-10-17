module LightStep
  # Scope represents an OpenTracing Scope
  #
  # See http://www.opentracing.io for more information.
  class Scope
    attr_reader :span

    def initialize(manager:, span:, finish_on_close: true)
      @manager = manager
      @span = span
      @finish_on_close = finish_on_close
    end

    # Mark the end of the active period for the current thread and Scope,
    # updating the ScopeManager#active in the process.
    def close
      raise(LightStep::Error, 'already closed') if @closed
      @closed = true
      @span.finish if @finish_on_close
      @manager.deactivate
    end
  end
end
