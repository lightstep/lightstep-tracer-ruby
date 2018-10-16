module LightStep
  class ScopeManager
    def initialize
      @scopes = []
    end

    def activate(span:, finish_on_close: true)
      return active if active && active.span == span
      scope = LightStep::Scope.new(manager: self, span: span, finish_on_close: finish_on_close)
      @scopes << scope
      scope
    end

    def active
      @scopes.last
    end

    def deactivate
      @scopes.pop
    end
  end
end
