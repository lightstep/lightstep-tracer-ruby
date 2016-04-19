require 'pp'
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

  it 'should handle nested spans' do
    tracer = init_test_tracer
    s0 = tracer.start_span('s0')
    s1 = tracer.start_span('s1', parent: s0)
    s2 = tracer.start_span('s2', parent: s1)
    s3 = tracer.start_span('s3', parent: s2)
    s4 = tracer.start_span('s4', parent: s3)
    s4.finish
    s3.finish
    s2.finish
    s1.finish
    s0.finish
  end

  it 'should report standard fields' do
    # "Report" to an object so we can examine the result
    result = nil
    tracer = LightStep.init_new_tracer(
      'lightstep/ruby/spec', '{your_access_token}',
      transport: 'callback',
      transport_callback: proc { |obj|; result = obj; })

    s0 = tracer.start_span('s0')
    s0.log_event('test_event')
    s0.finish
    tracer.flush

    expect(result).to include('runtime', 'span_records', 'log_records', 'oldest_micros', 'youngest_micros')

    expect(result['span_records'].length).to eq(1)
    expect(result['log_records'].length).to eq(1)
    expect(result['oldest_micros']).to be <= result['youngest_micros']

    # Decompose back into a plain hash
    runtime_attrs = Hash[result['runtime']['attrs'].map { |a|; [a['Key'], a['Value']]; }]
    expect(runtime_attrs).to include('lightstep_tracer_platform', 'lightstep_tracer_version')
    expect(runtime_attrs).to include('ruby_version')
  end
end
