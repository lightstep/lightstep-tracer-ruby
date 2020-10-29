require 'spec_helper'

describe LightStep::Propagation do
  let(:propagator_map) { LightStep::Propagation::PROPAGATOR_MAP }
  describe "[]" do
    it 'returns propagator instance from symbol' do
      propagator_map.each_pair do |sym, klass|
        propagator = LightStep::Propagation[sym]
        expect(propagator).to be_an_instance_of(klass)
      end
    end

    it 'returns propagator instance from a string' do
      propagator_map.each_pair do |sym, klass|
        propagator = LightStep::Propagation[sym.to_s]
        expect(propagator).to be_an_instance_of(klass)
      end
    end

    it 'returns lightstep propagator when name is unknown' do
      propagator = LightStep::Propagation[:this_propagator_is_unknown]
      expect(propagator).to be_an_instance_of(LightStep::Propagation::LightStepPropagator)
    end
  end
end
