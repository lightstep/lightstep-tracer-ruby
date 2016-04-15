require_relative '../lib/lightstep-tracer.rb'

describe LightStep do
    it "should return a new tracer from init_new_tracer" do
        tracer = LightStep.init_new_tracer('lightstep/ruby/spec', '{your_access_token}')
        expect(tracer).to be_an_instance_of ClientTracer
    end

    it "should return a valid span from start_span" do
        tracer = LightStep.init_new_tracer('lightstep/ruby/spec', '{your_access_token}')
        span = tracer.start_span('my_span')
        expect(span).to be_an_instance_of ClientSpan
        span.finish()
    end

    it "should allow support all the OpenTracing span APIs" do
        tracer = LightStep.init_new_tracer('lightstep/ruby/spec', '{your_access_token}')
        span = tracer.start_span('my_span')
        span.set_tag('key', 'value')
        span.set_baggage_item('baggage_key', 'baggage_item')
        span.log_event('event_name', { :key => 'value' })
        span.finish()
    end
end
