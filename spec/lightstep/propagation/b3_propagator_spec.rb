require 'spec_helper'

describe LightStep::Propagation::B3Propagator, :rack_helpers do
  let(:propagator) { subject }
  let(:trace_id_high_bytes) { LightStep.guid }
  let(:trace_id_low_bytes) { LightStep.guid }
  let(:trace_id) { [trace_id_high_bytes, trace_id_low_bytes].join }
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
  let(:span_context_trace_id_low_bytes) do
    LightStep::SpanContext.new(
      id: span_id,
      trace_id: trace_id_low_bytes,
      baggage: baggage
    )
  end
  let(:unsampled_span_context) do
    LightStep::SpanContext.new(
      id: span_id,
      trace_id: trace_id,
      sampled: true,
      baggage: baggage
    )
  end

  describe '#inject' do
    it 'handles text carriers' do
      carrier = {}
      propagator.inject(span_context, OpenTracing::FORMAT_TEXT_MAP, carrier)

      expect(carrier['x-b3-traceid']).to eq(trace_id)
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

      carrier = {}
      propagator.inject(span_context, OpenTracing::FORMAT_RACK, carrier)

      expect(carrier['x-b3-traceid']).to eq(trace_id)
      expect(carrier['x-b3-spanid']).to eq(span_id)
      expect(carrier['x-b3-sampled']).to eq('1')
      expect(carrier['ot-baggage-footwear']).to eq('cleats')
      expect(carrier['ot-baggage-umbrella']).to eq('golf')
      expect(carrier['ot-baggage-unsafeheader']).to be_nil
      expect(carrier['ot-baggage-CASE-Sensitivity_Underscores']).to eq('value')
    end

    it 'propagates a 16 byte trace id' do
      carrier = {}
      propagator.inject(span_context, OpenTracing::FORMAT_TEXT_MAP, carrier)

      expect(carrier['x-b3-traceid']).to eq(trace_id)
      expect(carrier['x-b3-traceid'].size).to eq(32)
    end

    it 'pads 8 byte trace_ids' do
      carrier = {}

      propagator.inject(span_context_trace_id_low_bytes, OpenTracing::FORMAT_RACK, carrier)
      expect(carrier['x-b3-traceid']).to eq('0' * 16 << trace_id_low_bytes)
      expect(carrier['x-b3-spanid']).to eq(span_id)
    end
  end

  describe '#extract' do
    it 'handles text carriers' do
      carrier = {}
      propagator.inject(span_context, OpenTracing::FORMAT_TEXT_MAP, carrier)
      extracted_ctx = propagator.extract(OpenTracing::FORMAT_TEXT_MAP, carrier)

      expect(extracted_ctx.trace_id).to eq(trace_id_low_bytes)
      expect(extracted_ctx.trace_id16).to eq(trace_id)
      expect(extracted_ctx.id).to eq(span_id)
      expect(extracted_ctx.baggage['footwear']).to eq('cleats')
      expect(extracted_ctx.baggage['umbrella']).to eq('golf')
    end

    it 'handles rack carriers' do
      baggage.merge!({
        'unsafe!@#$%$^&header' => 'value',
        'CASE-Sensitivity_Underscores'=> 'value'
      })

      carrier = {}
      propagator.inject(span_context, OpenTracing::FORMAT_RACK, carrier)
      extracted_ctx = propagator.extract(OpenTracing::FORMAT_RACK, to_rack_env(carrier))

      expect(extracted_ctx.trace_id).to eq(trace_id_low_bytes)
      expect(extracted_ctx.trace_id16).to eq(trace_id)
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
        {'HTTP_X_B3_TRACEID' => trace_id}
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
        {'HTTP_X_B3_SPANID' => span_id, 'HTTP_X_B3_TRACEID' => trace_id}
      )
      expect(extracted_ctx.id).to eq(span_id)
      expect(extracted_ctx.trace_id16).to eq(trace_id)
      expect(extracted_ctx.trace_id).to eq(trace_id_low_bytes)
    end

    it 'handles carriers with string keys' do
      carrier_with_strings = {
        'HTTP_X_B3_TRACEID' => trace_id,
        'HTTP_X_B3_SPANID' => span_id,
        'HTTP_X_B3_SAMPLED' => '1'
      }
      string_ctx = propagator.extract(OpenTracing::FORMAT_RACK, carrier_with_strings)

      expect(string_ctx).not_to be_nil
      expect(string_ctx.trace_id16).to eq(trace_id)
      expect(string_ctx.trace_id).to eq(trace_id_low_bytes)
      expect(string_ctx).to be_sampled
      expect(string_ctx.id).to eq(span_id)
    end

    it 'handles carriers symbol keys' do
      carrier_with_symbols = {
        HTTP_X_B3_TRACEID: trace_id,
        HTTP_X_B3_SPANID: span_id,
        HTTP_X_B3_SAMPLED: '1'
      }
      symbol_ctx = propagator.extract(OpenTracing::FORMAT_RACK, carrier_with_symbols)

      expect(symbol_ctx).not_to be_nil
      expect(symbol_ctx.trace_id16).to eq(trace_id)
      expect(symbol_ctx.trace_id).to eq(trace_id_low_bytes)
      expect(symbol_ctx).to be_sampled
      expect(symbol_ctx.id).to eq(span_id)
    end

    it 'pads 8 byte trace_ids' do
      carrier = {
        'x-b3-traceid' => trace_id_low_bytes,
        'x-b3-spanid' => span_id,
        'x-b3-sampled' => '1'
      }

      extracted_ctx = propagator.extract(OpenTracing::FORMAT_TEXT_MAP, carrier)
      expect(extracted_ctx.trace_id16).to eq('0' * 16 << trace_id_low_bytes)
      expect(extracted_ctx.trace_id).to eq(trace_id_low_bytes)
    end

    it 'interprets a true sampled flag properly' do
      carrier = {
        'x-b3-traceid' => trace_id,
        'x-b3-spanid' => span_id,
        'x-b3-sampled' => '1'
      }

      extracted_ctx = propagator.extract(OpenTracing::FORMAT_TEXT_MAP, carrier)
      expect(extracted_ctx).to be_sampled
    end

    it 'interprets a false sampled flag properly' do
      carrier = {
        'x-b3-traceid' => trace_id,
        'x-b3-spanid' => span_id,
        'x-b3-sampled' => '0'
      }

      extracted_ctx = propagator.extract(OpenTracing::FORMAT_TEXT_MAP, carrier)
      expect(extracted_ctx).not_to be_sampled
    end

    it 'maintains 8 and 16 byte trace ids' do
      carrier = {}
      propagator.inject(span_context, OpenTracing::FORMAT_TEXT_MAP, carrier)

      extracted_ctx = propagator.extract(OpenTracing::FORMAT_TEXT_MAP, carrier)
      expect(extracted_ctx.trace_id16).to eq(trace_id)
      expect(extracted_ctx.trace_id16.size).to eq(32)
      expect(extracted_ctx.trace_id).to eq(trace_id_low_bytes)
      expect(extracted_ctx.trace_id.size).to eq(16)
    end
  end
end
