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

    context 'when an active scope exists for a different span' do
      before(:each) do
        @span_1 = instance_spy(LightStep::Span)
        @scope_1 = scope_manager.activate(span: @span_1)
      end

      context 'when a new span is activated' do
        before(:each) do
          @span_2 = instance_spy(LightStep::Span)
          @scope_2 = scope_manager.activate(span: @span_2)
        end

        it 'should return a new scope' do
          expect(@scope_2).not_to eq(@scope_1)
        end
      end
    end

    context 'when an active scope exists for the same span' do
      before(:each) do
        scope_manager.activate(span: span)
      end

      it 'does not create a new scope' do
        expect(scope_manager.active).to eq(scope)
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
        @scope_1 = scope_manager.activate(span: span)
      end

      it 'should return the active scope' do
        scope = scope_manager.active
        expect(scope).not_to be_nil
        expect(scope.span).to eq(span)
      end

      context 'when the last active scope is closed' do
        before(:each) do
          @scope_1.close
        end

        it 'should return nil' do
          expect(scope_manager.active).to be_nil
        end
      end

      context 'when a new span is activated' do
        before(:each) do
          @span_2 = instance_spy(LightStep::Span)
          @scope_2 = scope_manager.activate(span: @span_2)
        end

        context 'when the new scope is closed' do
          before(:each) do
            @scope_2.close
          end

          it 'should return the old scope' do
            expect(scope_manager.active).to eq(@scope_1)
          end
        end
      end
    end
  end
end
