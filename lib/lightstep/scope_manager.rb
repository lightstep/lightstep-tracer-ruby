module LightStep
  class ScopeManager
    def activate(span:, finish_on_close: true)
      @scope = LightStep::Scope.new(span: span, finish_on_close: finish_on_close)
    end

    def active
      @scope if @scope
    end
  end
end
