require 'spec_helper'

describe LightStep::Propagation::B3Propagator, :rack_helpers do
  let(:propagator) { subject }
  let(:trace_id64) { LightStep.guid }
  let(:trace_id_upper64) { LightStep.guid }
  let(:trace_id128) { [trace_id_upper64, trace_id64].join }
  let(:span_id) { LightStep.guid }
  let(:baggage) do
    {
      'footwear' => 'cleats',
      'umbrella' => 'golf'
    }
  end
  let(:span_context_64bit_id) do
    LightStep::SpanContext.new(
      id: span_id,
      trace_id: trace_id64,
      baggage: baggage
    )
  end
  let(:span_context_128bit_id) do
    LightStep::SpanContext.new(
      id: span_id,
      trace_id: trace_id64,
      trace_id_upper64: trace_id_upper64,
      baggage: baggage
    )
  end
  let(:unsampled_span_context) do
    LightStep::SpanContext.new(
      id: span_id,
      trace_id: trace_id64,
      sampled: true,
      baggage: baggage
    )
  end

  describe '#inject' do
    it 'handles text carriers' do
      span_context = span_context_64bit_id
      carrier = {}
      propagator.inject(span_context, OpenTracing::FORMAT_TEXT_MAP, carrier)

      expect(carrier['x-b3-traceid']).to eq(trace_id64)
      expect(carrier['x-b3-spanid']).to eq(span_id)
      expect(carrier['x-b3-sampled']).to eq('1')
      expect(carrier['ot-baggage-footwear']).to eq('cleats')
      expect(carrier['ot-baggage-umbrella']).to eq('golf')
    end

    it 'handles rack carriers' do
      baggage.merge!({
        'unsafe!@#$%$^&header' => 'value',
        'CASE-Sensitivity_Underscores'=> 'value'
      })

      span_context = span_context_64bit_id
      carrier = {}
      propagator.inject(span_context, OpenTracing::FORMAT_RACK, carrier)

      expect(carrier['x-b3-traceid']).to eq(trace_id64)
      expect(carrier['x-b3-spanid']).to eq(span_id)
      expect(carrier['x-b3-sampled']).to eq('1')
      expect(carrier['ot-baggage-footwear']).to eq('cleats')
      expect(carrier['ot-baggage-umbrella']).to eq('golf')
      expect(carrier['ot-baggage-unsafeheader']).to be_nil
      expect(carrier['ot-baggage-CASE-Sensitivity_Underscores']).to eq('value')
    end

    it 'propagates 64 bit trace id when original is 64 bits' do
      span_context = span_context_64bit_id
      carrier = {}
      propagator.inject(span_context, OpenTracing::FORMAT_TEXT_MAP, carrier)

      expect(carrier['x-b3-traceid']).to eq(trace_id64)
      expect(carrier['x-b3-traceid'].size).to eq(16)
    end

    it 'propagates 128 bit trace id when original is 128 bits' do
      span_context = span_context_128bit_id
      carrier = {}
      propagator.inject(span_context, OpenTracing::FORMAT_TEXT_MAP, carrier)

      expect(carrier['x-b3-traceid']).to eq(trace_id128)
      expect(carrier['x-b3-traceid'].size).to eq(32)
    end
  end

  describe '#extract' do
    it 'handles text carriers' do
      span_context = span_context_64bit_id
      carrier = {}
      propagator.inject(span_context, OpenTracing::FORMAT_TEXT_MAP, carrier)
      extracted_ctx = propagator.extract(OpenTracing::FORMAT_TEXT_MAP, carrier)

      expect(extracted_ctx.trace_id).to eq(trace_id64)
      expect(extracted_ctx.id).to eq(span_id)
      expect(extracted_ctx.baggage['footwear']).to eq('cleats')
      expect(extracted_ctx.baggage['umbrella']).to eq('golf')
    end

    it 'handles rack carriers' do
      baggage.merge!({
        'unsafe!@#$%$^&header' => 'value',
        'CASE-Sensitivity_Underscores'=> 'value'
      })

      span_context = span_context_64bit_id
      carrier = {}
      propagator.inject(span_context, OpenTracing::FORMAT_RACK, carrier)
      extracted_ctx = propagator.extract(OpenTracing::FORMAT_RACK, to_rack_env(carrier))

      expect(extracted_ctx.trace_id).to eq(trace_id64)
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
        {'HTTP_X_B3_TRACEID' => trace_id64}
      )

      expect(extracted_ctx).to be_nil
      extracted_ctx = propagator.extract(
        OpenTracing::FORMAT_RACK,
        {'HTTP_X_B3_SPANID' => span_id}
      )
      expect(extracted_ctx).to be_nil

      # We need both a TRACEID and SPANID; this has both so it should work.
      extracted_ctx = propagator.extract(
        OpenTracing::FORMAT_RACK,
        {'HTTP_X_B3_SPANID' => span_id, 'HTTP_X_B3_TRACEID' => trace_id64}
      )
      expect(extracted_ctx.id).to eq(span_id)
      expect(extracted_ctx.trace_id).to eq(trace_id64)
    end

    it 'handles carriers with string keys' do
      carrier_with_strings = {
        'HTTP_X_B3_TRACEID' => trace_id64,
        'HTTP_X_B3_SPANID' => span_id,
        'HTTP_X_B3_SAMPLED' => '1'
      }
      string_ctx = propagator.extract(OpenTracing::FORMAT_RACK, carrier_with_strings)

      expect(string_ctx).not_to be_nil
      expect(string_ctx.trace_id).to eq(trace_id64)
      expect(string_ctx).to be_sampled
      expect(string_ctx.id).to eq(span_id)
    end

    it 'handles carriers symbol keys' do
      carrier_with_symbols = {
        HTTP_X_B3_TRACEID: trace_id64,
        HTTP_X_B3_SPANID: span_id,
        HTTP_X_B3_SAMPLED: '1'
      }
      symbol_ctx = propagator.extract(OpenTracing::FORMAT_RACK, carrier_with_symbols)

      expect(symbol_ctx).not_to be_nil
      expect(symbol_ctx.trace_id).to eq(trace_id64)
      expect(symbol_ctx).to be_sampled
      expect(symbol_ctx.id).to eq(span_id)
    end

    it 'handles 64-bit trace ids' do
      carrier = {
        'x-b3-traceid' => trace_id64,
        'x-b3-spanid' => span_id,
        'x-b3-sampled' => '1'
      }

      extracted_ctx = propagator.extract(OpenTracing::FORMAT_TEXT_MAP, carrier)
      expect(extracted_ctx.trace_id).to eq(trace_id64)
      expect(extracted_ctx.id_truncated?).to be(false)
    end

    it 'handles 128-bit trace ids' do
      carrier = {
        'x-b3-traceid' => trace_id128,
        'x-b3-spanid' => span_id,
        'x-b3-sampled' => '1'
      }

      extracted_ctx = propagator.extract(OpenTracing::FORMAT_TEXT_MAP, carrier)
      expect(extracted_ctx.trace_id128).to eq(trace_id128)
      expect(extracted_ctx.trace_id).to eq(trace_id64)
      expect(extracted_ctx.id_truncated?).to be(true)
    end

    it 'interprets a true sampled flag properly' do
      carrier = {
        'x-b3-traceid' => trace_id64,
        'x-b3-spanid' => span_id,
        'x-b3-sampled' => '1'
      }

      extracted_ctx = propagator.extract(OpenTracing::FORMAT_TEXT_MAP, carrier)
      expect(extracted_ctx).to be_sampled
    end

    it 'interprets a false sampled flag properly' do
      carrier = {
        'x-b3-traceid' => trace_id64,
        'x-b3-spanid' => span_id,
        'x-b3-sampled' => '0'
      }

      extracted_ctx = propagator.extract(OpenTracing::FORMAT_TEXT_MAP, carrier)
      expect(extracted_ctx).not_to be_sampled
    end
  end
end
