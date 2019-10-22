require 'spec_helper'

describe LightStep::Propagation::LightStepPropagator, :rack_helpers do
  let(:propagator) { subject }
  let(:trace_id) { LightStep.guid }
  let(:padded_trace_id) { '0' * 16 << trace_id }
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

  describe '#inject' do
    it 'handles text carriers' do
      carrier = {}
      propagator.inject(span_context, OpenTracing::FORMAT_TEXT_MAP, carrier)

      expect(carrier['ot-tracer-traceid']).to eq(trace_id)
      expect(carrier['ot-tracer-spanid']).to eq(span_id)
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

      expect(carrier['ot-tracer-traceid']).to eq(trace_id)
      expect(carrier['ot-tracer-spanid']).to eq(span_id)
      expect(carrier['ot-baggage-footwear']).to eq('cleats')
      expect(carrier['ot-baggage-umbrella']).to eq('golf')
      expect(carrier['ot-baggage-unsafeheader']).to be_nil
      expect(carrier['ot-baggage-CASE-Sensitivity_Underscores']).to eq('value')
    end

    it 'propagates an 8 byte trace id' do
      carrier = {}
      propagator.inject(span_context, OpenTracing::FORMAT_TEXT_MAP, carrier)

      expect(carrier['ot-tracer-traceid']).to eq(trace_id)
      expect(carrier['ot-tracer-traceid'].size).to eq(16)
    end

    it 'always propagates a true sampled flag' do
      [true, false].each do |sampled|
        ctx = LightStep::SpanContext.new(
          id: span_id,
          trace_id: trace_id,
          sampled: sampled,
          baggage: baggage
        )
        carrier = {}
        propagator.inject(span_context, OpenTracing::FORMAT_TEXT_MAP, carrier)
        expect(carrier['ot-tracer-sampled']).to eq('true')
      end
    end
  end

  describe '#extract' do
    it 'handles text carriers' do
      carrier = {}
      propagator.inject(span_context, OpenTracing::FORMAT_TEXT_MAP, carrier)
      extracted_ctx = propagator.extract(OpenTracing::FORMAT_TEXT_MAP, carrier)

      expect(extracted_ctx.trace_id).to eq(trace_id)
      expect(extracted_ctx.trace_id16).to eq(padded_trace_id)
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

      expect(extracted_ctx.trace_id).to eq(trace_id)
      expect(extracted_ctx.trace_id16).to eq(padded_trace_id)
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
      expect(extracted_ctx.trace_id16).to eq(padded_trace_id)
    end

    it 'handles carriers with string keys' do
      carrier = {
        'HTTP_OT_TRACER_TRACEID' => trace_id,
        'HTTP_OT_TRACER_SPANID' => span_id,
      }
      extracted_ctx = propagator.extract(OpenTracing::FORMAT_RACK, carrier)

      expect(extracted_ctx).not_to be_nil
      expect(extracted_ctx.trace_id).to eq(trace_id)
      expect(extracted_ctx.trace_id16).to eq(padded_trace_id)
      expect(extracted_ctx.id).to eq(span_id)
    end

    it 'handles carriers with symbol keys' do
      carrier = {
        HTTP_OT_TRACER_TRACEID: trace_id,
        HTTP_OT_TRACER_SPANID: span_id,
      }
      extracted_ctx = propagator.extract(OpenTracing::FORMAT_RACK, carrier)

      expect(extracted_ctx).not_to be_nil
      expect(extracted_ctx.trace_id).to eq(trace_id)
      expect(extracted_ctx.trace_id16).to eq(padded_trace_id)
      expect(extracted_ctx.id).to eq(span_id)
    end

    it 'maintains 8 and 16 byte trace ids' do
      trace_id16 = [LightStep.guid, trace_id].join

      carrier = {
        'ot-tracer-traceid' => trace_id16,
        'ot-tracer-spanid' => span_id,
        'ot-tracer-sampled' => 'true'
      }

      extracted_ctx = propagator.extract(OpenTracing::FORMAT_TEXT_MAP, carrier)
      expect(extracted_ctx.trace_id16).to eq(trace_id16)
      expect(extracted_ctx.trace_id16.size).to eq(32)
      expect(extracted_ctx.trace_id).to eq(trace_id)
      expect(extracted_ctx.trace_id.size).to eq(16)
    end

    it 'always sets sampled: true on returned context' do
      ['true', 'false'].each do |sampled|
         carrier = {
            'ot-tracer-traceid' => trace_id,
            'ot-tracer-spanid' => span_id,
            'ot-tracer-sampled' => sampled
          }

        extracted_ctx = propagator.extract(OpenTracing::FORMAT_TEXT_MAP, carrier)
        expect(extracted_ctx).to be_sampled
      end
    end
  end
end
