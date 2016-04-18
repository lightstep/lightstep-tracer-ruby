require_relative '../lib/lightstep-tracer.rb'

def init_test_tracer
  LightStep.init_new_tracer('lightstep/ruby/spec', '{your_access_token}', transport: 'nil')
end

describe LightStep do
  it 'should return a new tracer from init_new_tracer' do
    tracer = init_test_tracer
    expect(tracer).to be_an_instance_of ClientTracer
  end

  it 'should return a valid span from start_span' do
    tracer = init_test_tracer
    span = tracer.start_span('my_span')
    expect(span).to be_an_instance_of ClientSpan
    span.finish
  end

  it 'should allow support all the OpenTracing span APIs' do
    tracer = init_test_tracer
    span = tracer.start_span('my_span')
    span.set_tag('key', 'value')
    span.set_baggage_item('baggage_key', 'baggage_item')
    span.log_event('event_name', key: 'value')
    span.finish
  end

  it 'should handle 100 spans being created' do
    tracer = init_test_tracer
    for i in 0..100
      span = tracer.start_span('my_span')
      span.finish
    end
  end

  it 'should handle 10,000 spans being created' do
    tracer = init_test_tracer
    for i in 0..10_000
      span = tracer.start_span('my_span')
      span.finish
    end
  end

  it 'should handle 10,000 logs being created' do
    tracer = init_test_tracer
    span = tracer.start_span('my_span')
    for i in 0..10_000
      span.log_event 'test log'
    end
    span.finish
  end

  it 'should handle all valid payloads types' do
    tracer = init_test_tracer
    span = tracer.start_span('test_span')
    data = [
      nil,
      TRUE, FALSE,
      0, -1, 1,
      0.0, -1.0, 1.0,
      '', 'a', 'a longer string',
      'long string' * 1000,
      :s, :symbol,
      [],
      [0, 1, 2, 3],
      0..1000,
      {},
      { a: 'apple', b: 'bagel' },
      { outer: { in: 'ner' } }
    ]
    data.each do |value|
      span.log_event 'test', value
    end
    span.finish
  end
end
