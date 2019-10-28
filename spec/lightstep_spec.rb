require 'spec_helper'

describe LightStep do
  def init_test_tracer
    LightStep::Tracer.new(component_name: 'lightstep/ruby/spec', transport: LightStep::Transport::Nil.new)
  end

  def init_callback_tracer(callback)
    LightStep::Tracer.new(
      component_name: 'lightstep/ruby/spec',
      transport: LightStep::Transport::Callback.new(callback: callback)
    )
  end

  it 'should return a new tracer from init_new_tracer' do
    tracer = init_test_tracer
    expect(tracer).to be_an_instance_of LightStep::Tracer
  end

  it 'should return a valid span from start_span' do
    tracer = init_test_tracer
    span = tracer.start_span('my_span')
    expect(span).to be_an_instance_of LightStep::Span
    span.finish
  end

  it 'should inherit baggage from parent spans' do
    tracer = init_test_tracer
    parent_span = tracer.start_span('parent_span')
    parent_span.set_baggage(test: 'value')
    child_span = tracer.start_span('child_span', child_of: parent_span.context)
    expect(child_span.context.baggage).to eq(parent_span.context.baggage)
  end

  it 'should inherit baggage from parent spans' do
    tracer = init_test_tracer
    parent_span = tracer.start_span('parent_span')
    parent_span.set_baggage(test: 'value')
    child_span = tracer.start_span('child_span', child_of: parent_span)
    expect(child_span.span_context.baggage).to eq(parent_span.span_context.baggage)
  end

  it 'should inherit baggage from a single referenced span context (follows_from)' do
    tracer = init_test_tracer
    parent_span = tracer.start_span('parent_span')
    parent_span.set_baggage(test: 'value')
    child_span = tracer.start_span('child_span', references: parent_span)
    expect(child_span.span_context.baggage).to eq(parent_span.span_context.baggage)
  end

  it 'should inherit baggage from referenced span contexts (follows_from)' do
    tracer = init_test_tracer
    parent_span = tracer.start_span('parent_span')
    parent_span.set_baggage(test: 'value')
    child_span = tracer.start_span('child_span', references: [parent_span.span_context])
    expect(child_span.span_context.baggage).to eq(parent_span.span_context.baggage)
  end

  it 'should inherit baggage from a single referenced span (follows_from)' do
    tracer = init_test_tracer
    parent_span = tracer.start_span('parent_span')
    parent_span.set_baggage(test: 'value')
    child_span = tracer.start_span('child_span', references: parent_span)
    expect(child_span.span_context.baggage).to eq(parent_span.span_context.baggage)
  end

  it 'should inherit baggage from referenced spans (follows_from)' do
    tracer = init_test_tracer
    parent_span = tracer.start_span('parent_span')
    parent_span.set_baggage(test: 'value')
    child_span = tracer.start_span('child_span', references: [parent_span])
    expect(child_span.span_context.baggage).to eq(parent_span.span_context.baggage)
  end

  it 'should inherit true sampled flag from parent span' do
    tracer = init_test_tracer
    parent_ctx = LightStep::SpanContext.new(id: LightStep.guid, trace_id: LightStep.guid, sampled: true)
    child_span = tracer.start_span('child_span', child_of: parent_ctx)
    expect(child_span.span_context).to be_sampled
  end

  it 'should inherit false sampled flag from parent span' do
    tracer = init_test_tracer
    parent_ctx = LightStep::SpanContext.new(id: LightStep.guid, trace_id: LightStep.guid, sampled: false)
    child_span = tracer.start_span('child_span', child_of: parent_ctx)
    expect(child_span.span_context).not_to be_sampled
  end

  it 'should allow operation_name updates' do
    tracer = init_test_tracer
    span = tracer.start_span('original')
    expect(span.operation_name).to eq('original')
    span.operation_name = 'updated'
    expect(span.operation_name).to eq('updated')
    span.finish
  end

  it 'should allow support all the OpenTracing span APIs' do
    tracer = init_test_tracer
    span = tracer.start_span('my_span')
    span.set_tag('key', 'value')
    span.set_tag('bool', true)
    span.set_tag('number', 500)
    span.set_tag('array', [:hello])
    span.set_baggage_item('baggage_key', 'baggage_item')
    span.log(event: 'event_name', key: 'value')
    span.log_kv(a: 1, b: 'c')
    span.finish
  end

  it 'should not allow SpanContext modification' do
    tracer = init_test_tracer
    span = tracer.start_span('my_span')
    context = span.context
    expect{context.baggage['foo'] = 'bar'}.to raise_error(RuntimeError)
    expect{context.id.slice!(0,1)}.to raise_error(RuntimeError)
    expect{context.trace_id.slice!(0,1)}.to raise_error(RuntimeError)
  end

  it 'should allow tag-setting at start_span time' do
    tracer = init_test_tracer
    span = tracer.start_span('my_span', tags: {'start_key' => 'start_val'})
    span.set_tag('during_key', 'during_val')
    expect(span.tags['start_key']).to eq('start_val')
    expect(span.tags['during_key']).to eq('during_val')
    span.finish
  end

  it 'should coerce all tag values into strings' do
    class SampleClass ; end
    tracer = init_test_tracer
    span = tracer.start_span('my_span', tags: {
        'number_key' => 1,
        'bool_key' => true,
        'float_key' => 2.19,
        'array_key' => [1,2,3],
        'float_with_underscore_key' => 1_234_567,
        'hash_key' => {'1' => 2},
        'object_key' => SampleClass.new }
    )
    span.tags.each do |_, v|
      expect(v.is_a?(String))
    end
    span.finish
  end

  it 'should handle 100 spans being created' do
    tracer = init_test_tracer
    100.times do
      span = tracer.start_span('my_span')
      span.finish
    end
  end

  it 'should handle 10,000 spans being created' do
    tracer = init_test_tracer
    10_000.times do
      span = tracer.start_span('my_span')
      span.finish
    end
  end

  it 'should handle 10,000 logs being created' do
    tracer = init_test_tracer
    span = tracer.start_span('my_span')
    10_000.times do
      span.log_kv key: 'value'
    end
    span.finish
  end

  it 'should generate string span guids' do
    tracer = init_test_tracer
    span = tracer.start_span('test_span')

    expect(span.context.id).to be_an_instance_of String
    span.finish
  end

  it 'should allow start and end times to be specified explicitly' do
    tracer = init_test_tracer

    t1 = Time.now
    t1_micros = (t1.to_f * 1E6).floor
    t2 = t1 + 60
    t2_micros = (t2.to_f * 1E6).floor

    span1 = tracer.start_span('test1', start_time: t1)
    span1.finish
    expect(span1.start_micros).to eq(t1_micros)

    span2 = tracer.start_span('test2')
    span2.finish(end_time: t1)
    expect(span2.end_micros).to eq(t1_micros)

    span3 = tracer.start_span('test3', start_time: t1)
    span3.finish(end_time: t2)
    expect(span3.start_micros).to eq(t1_micros)
    expect(span3.end_micros).to eq(t2_micros)
  end

  it 'should allow end time to be specified at finish time' do
    tracer = init_test_tracer

    t1 = Time.now
    t1_micros = (t1.to_f * 1E6).floor
    span = tracer.start_span('test')
    span.finish(end_time: t1)
    expect(span.end_micros).to eq(t1_micros)
  end

  it 'should assign the same trace_guid to child spans as the parent' do
    tracer = init_test_tracer
    parent1 = tracer.start_span('parent1')
    parent2 = tracer.start_span('parent2')

    children1 = (1..4).to_a.map { tracer.start_span('child', child_of: parent1.context) }
    children2 = (1..4).to_a.map { tracer.start_span('child', child_of: parent2.context) }

    children1.each do |child|
      expect(child.context.trace_id).to be_an_instance_of String
      expect(child.context.trace_id).to eq(parent1.context.trace_id)
      expect(child.context.trace_id).not_to eq(parent2.context.trace_id)
      expect(child.tags[:parent_span_guid]).to eq(parent1.context.id)
    end

    children2.each do |child|
      expect(child.context.trace_id).to be_an_instance_of String
      expect(child.context.trace_id).to eq(parent2.context.trace_id)
      expect(child.context.trace_id).not_to eq(parent1.context.trace_id)
      expect(child.tags[:parent_span_guid]).to eq(parent2.context.id)
    end

    children1.each(&:finish)
    children2.each(&:finish)
    parent1.finish
    parent2.finish

    (children1.concat children2).each do |child|
      thrift_data = child.to_h
      expect(thrift_data[:trace_guid]).to eq(child.context.trace_id)
    end
  end

  it 'should handle all valid field types' do
    tracer = init_test_tracer
    span = tracer.start_span('test_span')
    file = File.open('./lib/lightstep.rb', 'r')
    data = [
      nil,
      true, false,
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
      span.log_kv key: 'value'
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
    span.log_kv a: a
    span.finish
  end

  it 'should handle nested spans' do
    tracer = init_test_tracer
    s0 = tracer.start_span('s0')
    s1 = tracer.start_span('s1', child_of: s0.context)
    s2 = tracer.start_span('s2', child_of: s1.context)
    s3 = tracer.start_span('s3', child_of: s2.context)
    s4 = tracer.start_span('s4', child_of: s3.context)
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
    s0.log_kv(a: 'bc')
    s0.finish
    tracer.flush

    expect(result).to include(:runtime, :span_records, :oldest_micros, :youngest_micros)

    expect(result[:span_records].length).to eq(1)
    expect(result[:span_records][0][:log_records].length).to eq(1)
    expect(result[:oldest_micros]).to be <= result[:youngest_micros]

    # Decompose back into a plain hash
    runtime_attrs = Hash[result[:runtime][:attrs].map { |a|; [a[:Key], a[:Value]]; }]
    expect(runtime_attrs).to include('lightstep.tracer_platform', 'lightstep.tracer_version')
    expect(runtime_attrs).to include('lightstep.tracer_platform_version')
  end

  it 'should report that Span#log is deprecated' do
    tracer = init_test_tracer
    span = tracer.start_span('span')
    expect { span.log(event: 'event') }.to output(
      "Span#log is deprecated. Please use Span#log_kv instead.\n"
    ).to_stderr
  end

  it 'should delegate Span#log' do
    result = nil
    tracer = LightStep::Tracer.new(
      component_name: 'lightstep/ruby/spec',
      transport: LightStep::Transport::Callback.new(callback: proc { |obj|; result = obj; })
    )

    reported_fields = proc do |fields|
      span = tracer.start_span('span')
      span.log(event: 'test-event', key: 'value')
      span.finish
      tracer.flush

      expect(result[:span_records].length).to eq(1)
      expect(result[:span_records][0][:log_records].length).to eq(1)

      result[:span_records][0][:log_records][0][:fields]
    end

    expect(reported_fields[:event]).to include({ Key: 'event', Value: 'test-event' })
    expect(reported_fields[:key]).to include({ Key: 'key', Value: 'value' })
  end

  it 'should report payloads correctly' do
    # "Report" to an object so we can examine the result
    result = nil
    tracer = LightStep::Tracer.new(
      component_name: 'lightstep/ruby/spec',
      transport: LightStep::Transport::Callback.new(callback: proc { |obj|; result = obj; })
    )

    reported_fields = proc do |fields|
      s0 = tracer.start_span('s0')
      s0.log_kv(**fields)
      s0.finish
      tracer.flush
      JSON.generate(result[:span_records][0][:log_records][0][:fields])
    end

    # NOTE: these comparisons rely on Ruby generating a consistent ordering to
    # map keys

    expect(reported_fields.call({})).to eq(JSON.generate([]))
    expect(reported_fields.call(x: 'y')).to eq(JSON.generate([{Key: 'x', Value: 'y'}]))
    expect(reported_fields.call(x: 'y', a: 5, true: true)).to eq(JSON.generate([
      {Key: 'x', Value: 'y'},
      {Key: 'a', Value: '5'},
      {Key: 'true', Value: 'true'}
    ]))
  end

  it 'should report user-specified tracer-level tags' do
    result = nil
    tracer = LightStep::Tracer.new(
      component_name: 'lightstep/ruby/spec',
      transport: LightStep::Transport::Callback.new(callback: proc {|obj| result = obj }),
      tags: {
        "user-provided-string" => "value",
        "user-provided-number" => 12,
        "user-provided-array" => []
      }
    )
    s0 = tracer.start_span('s0')
    s0.log_kv
    s0.finish
    tracer.flush

    expect(result).to include(:runtime, :span_records, :oldest_micros, :youngest_micros)
    expect(result[:runtime][:attrs]).to include({Key: "user-provided-string", Value: "value"})
    expect(result[:runtime][:attrs]).to include({Key: "user-provided-number", Value: "12"})
    expect(result[:runtime][:attrs]).to include({Key: "user-provided-array", Value: "[]"})
  end

  it 'should handle inject/join for text carriers' do
    tracer = init_test_tracer
    span1 = tracer.start_span('test_span')
    span1.set_baggage_item('footwear', 'cleats')
    span1.set_baggage_item('umbrella', 'golf')

    carrier = {}

    tracer.inject(span1.context, OpenTracing::FORMAT_TEXT_MAP, carrier)
    expect(carrier['ot-tracer-traceid']).to eq(span1.context.trace_id)
    expect(carrier['ot-tracer-spanid']).to eq(span1.context.id)
    expect(carrier['ot-baggage-footwear']).to eq('cleats')
    expect(carrier['ot-baggage-umbrella']).to eq('golf')

    span_ctx = tracer.extract(OpenTracing::FORMAT_TEXT_MAP, carrier)
    expect(span_ctx.trace_id).to eq(span1.context.trace_id)
    expect(span_ctx.id).to eq(span1.context.id)
    expect(span_ctx.baggage['footwear']).to eq('cleats')
    expect(span_ctx.baggage['umbrella']).to eq('golf')

    span1.finish
  end

  it 'should handle inject/extract for http requests and rack' do
    tracer = init_test_tracer
    span1 = tracer.start_span('test_span')
    span1.set_baggage_item('footwear', 'cleats')
    span1.set_baggage_item('umbrella', 'golf')
    span1.set_baggage_item('unsafe!@#$%$^&header', 'value')
    span1.set_baggage_item('CASE-Sensitivity_Underscores', 'value')

    carrier = {}

    tracer.inject(span1.context, OpenTracing::FORMAT_RACK, carrier)
    expect(carrier['ot-tracer-traceid']).to eq(span1.context.trace_id)
    expect(carrier['ot-tracer-spanid']).to eq(span1.context.id)
    expect(carrier['ot-baggage-footwear']).to eq('cleats')
    expect(carrier['ot-baggage-umbrella']).to eq('golf')
    expect(carrier['ot-baggage-unsafeheader']).to be_nil
    expect(carrier['ot-baggage-CASE-Sensitivity_Underscores']).to eq('value')

    carrier = carrier.reduce({}) do |memo, tuple|
      key, value = tuple
      memo["HTTP_#{key.gsub("-", "_").upcase}"] = value
      memo
    end

    span_ctx = tracer.extract(OpenTracing::FORMAT_RACK, carrier)
    expect(span_ctx.trace_id).to eq(span1.context.trace_id)
    expect(span_ctx.id).to eq(span1.context.id)
    expect(span_ctx.baggage['footwear']).to eq('cleats')
    expect(span_ctx.baggage['umbrella']).to eq('golf')
    expect(span_ctx.baggage['unsafe!@#$%$^&header']).to be_nil
    expect(span_ctx.baggage['unsafeheader']).to be_nil
    expect(span_ctx.baggage['case-sensitivity-underscores']).to eq('value')

    # We need both a TRACEID and SPANID.
    span_ctx = tracer.extract(OpenTracing::FORMAT_RACK, {'HTTP_OT_TRACER_TRACEID' => 'abc123'})
    expect(span_ctx).to be_nil
    span_ctx = tracer.extract(OpenTracing::FORMAT_RACK, {'HTTP_OT_TRACER_SPANID' => 'abc123'})
    expect(span_ctx).to be_nil

    # We need both a TRACEID and SPANID; this has both so it should work.
    span_ctx = tracer.extract(OpenTracing::FORMAT_RACK, {'HTTP_OT_TRACER_SPANID' => 'abc123', 'HTTP_OT_TRACER_TRACEID' => 'bcd234'})
    expect(span_ctx.id).to eq('abc123')
    expect(span_ctx.trace_id).to eq('bcd234')

    span1.finish
  end

  it 'should be able to extract from a carrier with string or symbol keys' do
    trace_id = '123'
    span_id = 'abc'

    tracer = init_test_tracer

    carrier_with_strings = {
      'HTTP_OT_TRACER_TRACEID' => trace_id,
      'HTTP_OT_TRACER_SPANID' => span_id,
    }
    string_ctx = tracer.extract(OpenTracing::FORMAT_RACK, carrier_with_strings)

    expect(string_ctx).not_to be_nil
    expect(string_ctx.trace_id).to eq(trace_id)
    expect(string_ctx.id).to eq(span_id)

    carrier_with_symbols = {
      HTTP_OT_TRACER_TRACEID: trace_id,
      HTTP_OT_TRACER_SPANID: span_id,
    }
    symbol_ctx = tracer.extract(OpenTracing::FORMAT_RACK, carrier_with_symbols)

    expect(symbol_ctx).not_to be_nil
    expect(symbol_ctx.trace_id).to eq(trace_id)
    expect(symbol_ctx.id).to eq(span_id)
  end

  it 'should handle concurrent spans' do
    result = nil
    tracer = init_callback_tracer(proc { |obj|; result = obj; })
    parent = tracer.start_span('parent_span')
    threads = *(1..64).map do |i|
      Thread.new do
        child = tracer.start_span("child_span_#{i}")
        10.times do |j|
          sleep 0.01
          child.log_kv(j: j)
        end
        child.finish
      end
    end
    threads.each(&:join)
    parent.finish
    tracer.flush

    expect(result[:span_records].length).to eq(65)
    result[:span_records].each do |span|
      expect(span[:log_records].length).to eq(10) unless span[:span_name] == "parent_span"
    end

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
              child.log_kv(j: j)
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
      expect(r[:span_records].length).to eq(17)
      r[:span_records].each do |span|
        expect(span[:log_records].length).to eq(10) unless span[:span_name] == "parent_span"
        expect(span[:log_records].length).to eq(0) if span[:span_name] == "parent_span"
      end
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

  it 'should not be enabled after disabling' do
    tracer = init_callback_tracer(proc { |obj| result = obj })
    tracer.disable
    expect(tracer).not_to be_enabled
  end

  it 'should not report spans when disabled' do
    result = nil
    tracer = init_callback_tracer(proc { |obj| result = obj })
    tracer.disable
    Timecop.freeze(Time.now + 5 * 60) do
      tracer.start_span('span').finish
    end
    expect(result).to be_nil
  end

  it 'should report dropped spans and logs' do
    result = nil
    tracer = init_callback_tracer(proc { |obj| result = obj })
    tracer.max_span_records = 5
    tracer.max_log_records = 5

    (1..10).map do |i|
      Thread.new do
        span = tracer.start_span("span_#{i}")
        (1..10).map do |j|
          Thread.new do
            span.log_kv(j: j)
          end
        end.map(&:join)
        span.finish
      end
    end.map(&:join)
    tracer.flush
    expect(result[:internal_metrics][:counts]).to eq([
      {name: "spans.dropped", int64_value: 5}
    ])
  end

  it 'should have a String guid' do
    tracer = init_test_tracer
    expect(tracer.guid).to be_a(String)
  end

  it 'should include the tracer guid in the reported runtime' do
    result = nil
    tracer = init_callback_tracer(proc { |obj| result = obj })
    tracer.start_span('span').finish
    tracer.flush

    expect(result).to be_a(Hash)
    expect(result[:runtime][:guid]).to eq(tracer.guid)
  end

  it 'should include the tracer guid in reported spans' do
    result = nil
    tracer = init_callback_tracer(proc { |obj| result = obj })
    tracer.start_span('span').finish
    tracer.flush

    expect(result).to be_a(Hash)
    expect(result[:span_records].first[:runtime_guid]).to eq(tracer.guid)
  end

  it 'should convert span names to strings' do
    result = nil
    tracer = init_callback_tracer(proc { |obj| result = obj })
    tracer.start_span(5).finish
    tracer.start_span([:foo]).finish
    tracer.flush
    records = result[:span_records]
    expect(records[0][:span_name]).to eq("5")
    expect(records[1][:span_name]).to eq("[:foo]")
  end

  describe '#scope_manager' do
    let(:tracer) { init_test_tracer }

    it 'should return a scope manager' do
      expect(tracer.scope_manager).to be_an_instance_of(LightStep::ScopeManager)
    end

    context 'when the scope manager exists' do
      before(:each) do
        @manager = tracer.scope_manager
      end

      it 'should return the same scope manager' do
        expect(tracer.scope_manager).to eq(@manager)
      end
    end
  end

  describe '#start_span' do
    let(:tracer) { init_test_tracer }

    context 'when there is an active scope' do
      before(:each) do
        @scope = tracer.start_active_span('some-operation')
        @parent_span = @scope.span
      end

      it 'should create a child_of reference to the active scope' do
        span = tracer.start_span('child-operation')
        expect(span.tags[:parent_span_guid]).to eq(@parent_span.context.id)
      end

      context 'when ignore_active_scope is true' do
        it 'should not create a child_of reference to the active scope' do
          span = tracer.start_span('child-operation', ignore_active_scope: true)
          expect(span.tags[:parent_span_guid]).not_to eq(@parent_span.context.id)
        end
      end
    end

    context 'when a block is given' do
      before(:each) do
        @result = tracer.start_span('some-operation') do |span|
          allow(span).to receive(:finish)
          @span = span
          "some result"
        end
      end

      it 'should return the result of executing the block' do
        expect(@result).to eq("some result")
      end

      it 'should yield the span to the block' do
        expect(@span).to be_an_instance_of(LightStep::Span)
        expect(@span.to_h[:span_name]).to eq('some-operation')
      end

      it 'should finish the span before returning' do
        expect(@span).to have_received(:finish)
      end
    end
  end

  describe '#start_active_span' do
    let(:tracer) { init_test_tracer }

    it 'should set the active scope' do
      span = tracer.start_active_span('some-operation')

      actual = tracer.scope_manager.active
      expect(actual).to be_an_instance_of(LightStep::Scope)
      expect(actual.span.to_h[:span_name]).to eq('some-operation')
    end

    it 'should yield the active scope when given a block' do
      tracer.start_active_span('some-operation') do |scope|
        expect(scope).to be_an_instance_of(LightStep::Scope)

        expected_scope = tracer.scope_manager.active
        expect(scope).to eq(expected_scope)
        expect(scope.span.to_h[:span_name]).to eq('some-operation')
      end
    end

    context 'when a block is given' do
      before(:each) do
        @result = tracer.start_active_span('some-operation') do |scope|
          @scope = scope
          expect(@scope.span.end_micros).to be_nil
          "some result"
        end
      end

      it 'should finish the span' do
        expect(@scope.span.end_micros).not_to be_nil
      end

      it 'should return the result of executing the block' do
        expect(@result).to eq("some result")
      end
    end

    context 'when finish_on_close is false and a block is given' do
      before(:each) do
        tracer.start_active_span('some-operation', finish_on_close: false) do |scope|
          @scope = scope
          expect(@scope.span.end_micros).to be_nil
        end
      end

      it 'should not finish the span after the block finishes yielding' do
        expect(@scope.span.end_micros).to be_nil
      end
    end

    context 'when there is an active scope' do
      let!(:parent_span) { tracer.start_active_span('some-operation').span }
      let(:scope) { tracer.start_active_span('child-operation') }

      it 'should create a child_of reference to the active scope' do
        expect(scope.span.tags[:parent_span_guid]).to eq(parent_span.context.id)
      end

      context 'when ignore_active_scope is true' do
        let(:scope) { tracer.start_active_span('child-operation', ignore_active_scope: true) }

        it 'should not create a child_of reference to the active scope', focus: true do
          expect(scope.span.tags[:parent_span_guid]).not_to eq(parent_span.context.id)
        end
      end
    end

    xit 'should create a span with the given operation_name'
    xit 'should create a span with the given child_of'
    xit 'should create a span with the given references'
    xit 'should create a span with the given start_time'
    xit 'should create a span with the given tags'
  end

  describe '#active_span' do
    let(:tracer) { init_test_tracer }

    it 'should return nil' do
      expect(tracer.active_span).to be_nil
    end

    context 'when there is an active scope' do
      before(:each) do
        scope = tracer.start_active_span('some-operation')
      end

      it 'should return the active span' do
        expect(tracer.active_span.to_h[:span_name]).to eq('some-operation')
      end
    end
  end
end
