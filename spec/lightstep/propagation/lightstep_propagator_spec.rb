require 'spec_helper'

describe LightStep::Propagation::LightStepPropagator do
  let(:propagator) { subject }
  let(:trace_id) { LightStep.guid }
  let(:span_id) { LightStep.guid }
  let(:baggage) do
    {
      'footwear' => 'cleats',
      'umbrella' => 'golf'
    }
  end
  let(:span_context) do
    LightStep::SpanContext.new(
      id: span_id,
      trace_id: trace_id,
      baggage: baggage
    )
  end

  it 'should handle inject/join for text carriers' do
    carrier = {}

    propagator.inject(span_context, OpenTracing::FORMAT_TEXT_MAP, carrier)
    expect(carrier['ot-tracer-traceid']).to eq(trace_id)
    expect(carrier['ot-tracer-spanid']).to eq(span_id)
    expect(carrier['ot-baggage-footwear']).to eq('cleats')
    expect(carrier['ot-baggage-umbrella']).to eq('golf')

    extracted_ctx = propagator.extract(OpenTracing::FORMAT_TEXT_MAP, carrier)
    expect(extracted_ctx.trace_id).to eq(trace_id)
    expect(extracted_ctx.id).to eq(span_id)
    expect(extracted_ctx.baggage['footwear']).to eq('cleats')
    expect(extracted_ctx.baggage['umbrella']).to eq('golf')
  end

  it 'should handle inject/extract for http requests and rack' do
    baggage.merge!({
      'unsafe!@#$%$^&header' => 'value',
      'CASE-Sensitivity_Underscores'=> 'value'
    })

    carrier = {}

    propagator.inject(span_context, OpenTracing::FORMAT_RACK, carrier)
    expect(carrier['ot-tracer-traceid']).to eq(trace_id)
    expect(carrier['ot-tracer-spanid']).to eq(span_id)
    expect(carrier['ot-baggage-footwear']).to eq('cleats')
    expect(carrier['ot-baggage-umbrella']).to eq('golf')
    expect(carrier['ot-baggage-unsafeheader']).to be_nil
    expect(carrier['ot-baggage-CASE-Sensitivity_Underscores']).to eq('value')

    extracted_ctx = propagator.extract(OpenTracing::FORMAT_RACK, to_rack_env(carrier))
    expect(extracted_ctx.trace_id).to eq(trace_id)
    expect(extracted_ctx.id).to eq(span_id)
    expect(extracted_ctx.baggage['footwear']).to eq('cleats')
    expect(extracted_ctx.baggage['umbrella']).to eq('golf')
    expect(extracted_ctx.baggage['unsafe!@#$%$^&header']).to be_nil
    expect(extracted_ctx.baggage['unsafeheader']).to be_nil
    expect(extracted_ctx.baggage['case-sensitivity-underscores']).to eq('value')
  end

  it 'returns a span context when carrier has both a span_id and trace_id' do
    extracted_ctx = propagator.extract(
      OpenTracing::FORMAT_RACK,
      {'HTTP_OT_TRACER_TRACEID' => trace_id}
    )

    expect(extracted_ctx).to be_nil
    extracted_ctx = propagator.extract(
      OpenTracing::FORMAT_RACK,
      {'HTTP_OT_TRACER_SPANID' => span_id}
    )
    expect(extracted_ctx).to be_nil

    # We need both a TRACEID and SPANID; this has both so it should work.
    extracted_ctx = propagator.extract(
      OpenTracing::FORMAT_RACK,
      {'HTTP_OT_TRACER_SPANID' => span_id, 'HTTP_OT_TRACER_TRACEID' => trace_id}
    )
    expect(extracted_ctx.id).to eq(span_id)
    expect(extracted_ctx.trace_id).to eq(trace_id)
  end

  it 'should be able to extract from a carrier with string or symbol keys' do
    carrier_with_strings = {
      'HTTP_OT_TRACER_TRACEID' => trace_id,
      'HTTP_OT_TRACER_SPANID' => span_id,
    }
    string_ctx = propagator.extract(OpenTracing::FORMAT_RACK, carrier_with_strings)

    expect(string_ctx).not_to be_nil
    expect(string_ctx.trace_id).to eq(trace_id)
    expect(string_ctx.id).to eq(span_id)

    carrier_with_symbols = {
      HTTP_OT_TRACER_TRACEID: trace_id,
      HTTP_OT_TRACER_SPANID: span_id,
    }
    symbol_ctx = propagator.extract(OpenTracing::FORMAT_RACK, carrier_with_symbols)

    expect(symbol_ctx).not_to be_nil
    expect(symbol_ctx.trace_id).to eq(trace_id)
    expect(symbol_ctx.id).to eq(span_id)
  end

  def to_rack_env(input_hash)
    input_hash.inject({}) do |memo, (k, v)|
      memo[to_rack_key(k)] = v
      memo
    end
  end

  def to_rack_key(key)
    "HTTP_#{key.gsub("-", "_").upcase!}"
  end
end