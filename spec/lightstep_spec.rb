require_relative '../lightstep.rb'

describe LightStep do
    it "should return a new tracer from init_new_tracer" do
        tracer = LightStep.init_new_tracer('lightstep/ruby/spec', '{your_access_token}')
        expect(tracer).to be_an_instance_of ClientTracer
    end
end
