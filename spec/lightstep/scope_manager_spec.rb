require 'spec_helper'

describe 'LightStep:ScopeManager' do
  let(:scope_manager) { LightStep::ScopeManager.new }
  let(:span) { instance_spy(LightStep::Span) }

  describe '#activate' do
    let(:scope) { scope_manager.activate(span: span) }

    it 'should return a scope' do
      expect(scope).to be_instance_of(LightStep::Scope)
    end

    it 'should set the span on the returned scope' do
      expect(scope.span).to eq(span)
    end

    it 'should raise an error when no span is given' do
      expect { scope_manager.activate }.to raise_error(ArgumentError)
    end

    context 'when finish_on_close is true' do
      let(:scope) { scope_manager.activate(span: span, finish_on_close: true) }

      it 'should finish the span when the scope is closed' do
        expect(span).to receive(:finish)
        scope.close
      end
    end
  end

  describe '#active' do
    it 'should return nil' do
      expect(scope_manager.active).to be_nil
    end

    context 'when there is an active scope' do
      let(:span) { instance_spy(LightStep::Span) }

      before(:each) do
        @scope = scope_manager.activate(span: span)
      end

      it 'should return the active scope' do
        scope = scope_manager.active
        expect(scope).not_to be_nil
        expect(scope.span).to eq(span)
      end

      context 'when the active scope was closed' do
        before(:each) do
          @scope.close
        end

        it 'should return nil' do
          expect(scope_manager.active).to be_nil
        end
      end
    end
  end
end
