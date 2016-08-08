require 'pp'
require_relative '../lib/lightstep-tracer.rb'

def init_test_tracer
  LightStep.init_new_tracer('lightstep/ruby/spec', '{your_access_token}', transport: 'nil')
end

def init_callback_tracer(callback)
  tracer = LightStep.init_new_tracer(
    'lightstep/ruby/spec', '{your_access_token}',
    transport: 'callback',
    transport_callback: callback)
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

  it 'should generate string span guids' do
    tracer = init_test_tracer
    span = tracer.start_span('test_span')

    expect(span.guid).to be_an_instance_of String
    span.finish
  end

  it 'should allow start and end times to be specified explicitly' do
    tracer = init_test_tracer

    span1 = tracer.start_span('test1', startTime: 1000)
    span1.finish
    expect(span1.start_micros).to eq(1000 * 1000)

    span2 = tracer.start_span('test2', endTime: 54_321)
    span2.finish
    expect(span2.end_micros).to eq(54_321 * 1000)

    span3 = tracer.start_span('test3', startTime: 1234, endTime: 5678)
    span3.finish
    expect(span3.start_micros).to eq(1234 * 1000)
    expect(span3.end_micros).to eq(5678 * 1000)
  end

  it 'should assign the same trace_guid to child spans as the parent' do
    tracer = init_test_tracer
    parent1 = tracer.start_span('parent1')
    parent2 = tracer.start_span('parent2')

    children1 = (1..4).to_a.map { |_i| tracer.start_span('child', parent: parent1) }
    children2 = (1..4).to_a.map { |_i| tracer.start_span('child', parent: parent2) }

    children1.each do |child|
      expect(child.trace_guid).to be_an_instance_of String
      expect(child.trace_guid).to eq(parent1.trace_guid)
      expect(child.trace_guid).not_to eq(parent2.trace_guid)
    end

    children2.each do |child|
      expect(child.trace_guid).to be_an_instance_of String
      expect(child.trace_guid).to eq(parent2.trace_guid)
      expect(child.trace_guid).not_to eq(parent1.trace_guid)
    end

    children1.each(&:finish)
    children2.each(&:finish)
    parent1.finish
    parent2.finish

    (children1.concat children2).each do |child|
      thrift_data = child.to_thrift
      expect(thrift_data.trace_guid).to eq(child.trace_guid)
    end
  end

  it 'should handle all valid payloads types' do
    tracer = init_test_tracer
    span = tracer.start_span('test_span')
    file = File.open('./lib/lightstep-tracer.rb', 'r')
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
      { outer: { in: 'ner' } },
      STDOUT,
      STDERR,
      STDIN,
      file,
      nil::NilClass
    ]
    data.each do |value|
      span.log_event 'test', value
    end
    span.finish
    file.close
  end

  it 'should handle payloads with circular references' do
    a = { value: 7, next: nil }
    b = { value: 42, next: nil }
    a['next'] = b
    b['next'] = a

    tracer = init_test_tracer
    span = tracer.start_span('test_span')
    span.log_event 'circular_ref', a
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
    tracer = init_callback_tracer(proc { |obj|; result = obj; })
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

  it 'should report payloads correctly' do
    # "Report" to an object so we can examine the result
    result = nil
    tracer = LightStep.init_new_tracer(
      'lightstep/ruby/spec', '{your_access_token}',
      transport: 'callback',
      transport_callback: proc { |obj|; result = obj; })

    single_payload = proc do |payload|
      s0 = tracer.start_span('s0')
      s0.log_event('test_event', payload)
      s0.finish
      tracer.flush
      JSON.generate(JSON.parse(result['log_records'][0]['payload_json']))
    end

    # NOTE: these comparisons rely on Ruby generating a consistent ordering to
    # map keys

    # TODO: these tests are aligned to the current behavior that primitive types
    # are prefixed with a "payload" key
    expect(single_payload.call(0)).to eq(JSON.generate(payload: 0))
    expect(single_payload.call(-1)).to eq(JSON.generate(payload: -1))
    expect(single_payload.call('test')).to eq(JSON.generate(payload: 'test'))
    expect(single_payload.call(true)).to eq(JSON.generate(payload: true))

    expect(single_payload.call([])).to eq(JSON.generate([]))
    expect(single_payload.call([1, 2, 3])).to eq(JSON.generate([1, 2, 3]))
    expect(single_payload.call({})).to eq(JSON.generate({}))
    expect(single_payload.call(x: 'y')).to eq(JSON.generate(x: 'y'))
    expect(single_payload.call(x: 'y', a: 'b')).to eq(JSON.generate(x: 'y', a: 'b'))
  end

  it 'should handle inject/join for text carriers' do
    tracer = init_test_tracer
    span1 = tracer.start_span('test_span')
    span1.set_baggage_item('footwear', 'cleats')
    span1.set_baggage_item('umbrella', 'golf')

    carrier = {}
    tracer.inject(span1, LightStep.FORMAT_TEXT_MAP, carrier)
    expect(carrier['ot-tracer-traceid']).to eq(span1.trace_guid)
    expect(carrier['ot-tracer-spanid']).to eq(span1.guid)
    expect(carrier['ot-baggage-footwear']).to eq('cleats')
    expect(carrier['ot-baggage-umbrella']).to eq('golf')

    span2 = tracer.join('test_span_2', LightStep.FORMAT_TEXT_MAP, carrier)
    expect(span2.trace_guid).to eq(span1.trace_guid)
    expect(span2.parent_guid).to eq(span1.guid)
    expect(span2.get_baggage_item('footwear')).to eq('cleats')
    expect(span2.get_baggage_item('umbrella')).to eq('golf')

    span1.finish
    span2.finish
  end

  it 'should handle concurrent spans' do
    result = nil
    tracer = init_callback_tracer(proc { |obj|; result = obj; })
    parent = tracer.start_span('parent_span')
    threads = *(1..64).map do |i|
      Thread.new do
        child = tracer.start_span("child_span_#{i}")
        for j in 1..10
          sleep 0.01
          child.log_event('message', j)
        end
        child.finish
      end
    end
    threads.each(&:join)
    parent.finish
    tracer.flush

    expect(result['span_records'].length).to eq(65)
    expect(result['log_records'].length).to eq(64 * 10)
  end

  it 'should handle concurrent tracers' do
    results = {}
    outer_threads = *(1..8).to_a.map do |k|
                      Thread.new do
                        tracer = init_callback_tracer(proc { |obj|; results[k] = obj; })
                        parent = tracer.start_span('parent_span')
                        threads = *(1..16).map do |i|
                          Thread.new do
                            child = tracer.start_span("child_span_#{i}")
                            for j in 1..10
                              sleep 0.01
                              child.log_event('message', j)
                            end
                            child.finish
                          end
                        end
                        threads.each(&:join)
                        parent.finish

                        tracer.flush
                      end
                    end
    outer_threads.each(&:join)
    for i in 1..8
      r = results[i]
      expect(r['span_records'].length).to eq(17)
      expect(r['log_records'].length).to eq(16 * 10)
    end
  end

  # NOTE: this is a relatively weak test since it is using the test transport
  # which is very simply (rather than the actual HTTP transport and background
  # thread).
  it 'should support disable and enable in sequence' do
    tracer = init_callback_tracer(proc { |obj|; result = obj; })
    for i in 1..4
      tracer.disable
      tracer.enable
    end

    tracer.disable
    tracer.disable
    tracer.disable

    tracer.enable
    tracer.enable
    tracer.enable
  end
end
