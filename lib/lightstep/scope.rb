module LightStep
  class Scope
    attr_reader :span

    def initialize(span:, finish_on_close: true)
      @span = span
      @finish_on_close = finish_on_close
    end

    def close
      raise LightStep::Error.new('already closed') if @closed
      @closed = true
      @span.finish if @finish_on_close
    end
  end
end
