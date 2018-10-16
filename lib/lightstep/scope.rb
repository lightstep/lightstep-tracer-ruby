module LightStep
  class Scope
    attr_reader :span

    def initialize(manager:, span:, finish_on_close: true)
      @manager = manager
      @span = span
      @finish_on_close = finish_on_close
    end

    def close
      raise(LightStep::Error, 'already closed') if @closed
      @closed = true
      @span.finish if @finish_on_close
      @manager.deactivate
    end
  end
end
