#frozen_string_literal: true

module LightStep
  module Propagation
    class LightStepPropagator
      CARRIER_TRACER_STATE_PREFIX = 'ot-tracer-'
      CARRIER_SPAN_ID = 'ot-tracer-spanid'
      CARRIER_TRACE_ID = 'ot-tracer-traceid'
      CARRIER_SAMPLED = 'ot-tracer-sampled'
      CARRIER_BAGGAGE_PREFIX = 'ot-baggage-'

      # Inject a SpanContext into the given carrier
      #
      # @param spancontext [SpanContext]
      # @param format [OpenTracing::FORMAT_TEXT_MAP, OpenTracing::FORMAT_BINARY]
      # @param carrier [Carrier] A carrier object of the type dictated by the specified `format`
      def inject(span_context, format, carrier)
        case format
        when OpenTracing::FORMAT_TEXT_MAP
          inject_to_text_map(span_context, carrier)
        when OpenTracing::FORMAT_BINARY
          warn 'Binary inject format not yet implemented'
        when OpenTracing::FORMAT_RACK
          inject_to_rack(span_context, carrier)
        else
          warn 'Unknown inject format'
        end
      end

      # Extract a SpanContext from a carrier
      # @param format [OpenTracing::FORMAT_TEXT_MAP, OpenTracing::FORMAT_BINARY, OpenTracing::FORMAT_RACK]
      # @param carrier [Carrier] A carrier object of the type dictated by the specified `format`
      # @return [SpanContext] the extracted SpanContext or nil if none could be found
      def extract(format, carrier)
        case format
        when OpenTracing::FORMAT_TEXT_MAP
          extract_from_text_map(carrier)
        when OpenTracing::FORMAT_BINARY
          warn 'Binary join format not yet implemented'
          nil
        when OpenTracing::FORMAT_RACK
          extract_from_rack(carrier)
        else
          warn 'Unknown join format'
          nil
        end
      end

      private

      def inject_to_text_map(span_context, carrier)
        if trace_id = trace_id_from_ctx(span_context)
          carrier[self.class::CARRIER_TRACE_ID] = trace_id
        end
        carrier[self.class::CARRIER_SPAN_ID] = span_context.id
        carrier[self.class::CARRIER_SAMPLED] = 'true'

        span_context.baggage.each do |key, value|
          carrier[self.class::CARRIER_BAGGAGE_PREFIX + key] = value
        end
      end

      def extract_from_text_map(carrier)
        # If the carrier does not have both the span_id and trace_id key
        # skip the processing and just return a normal span
        if !carrier.has_key?(self.class::CARRIER_SPAN_ID) || !carrier.has_key?(self.class::CARRIER_TRACE_ID)
          return nil
        end

        baggage = carrier.reduce({}) do |baggage, (key, value)|
          if key.start_with?(self.class::CARRIER_BAGGAGE_PREFIX)
            plain_key = key.to_s[self.class::CARRIER_BAGGAGE_PREFIX.length..key.to_s.length]
            baggage[plain_key] = value
          end
          baggage
        end

        SpanContext.new(
          id: carrier[self.class::CARRIER_SPAN_ID],
          trace_id: carrier[self.class::CARRIER_TRACE_ID],
          baggage: baggage,
        )
      end

      def inject_to_rack(span_context, carrier)
        if trace_id = trace_id_from_ctx(span_context)
          carrier[self.class::CARRIER_TRACE_ID] = trace_id
        end
        carrier[self.class::CARRIER_SPAN_ID] = span_context.id
        carrier[self.class::CARRIER_SAMPLED] = 'true'

        span_context.baggage.each do |key, value|
          if key =~ /[^A-Za-z0-9\-_]/
            # TODO: log the error internally
            next
          end
          carrier[self.class::CARRIER_BAGGAGE_PREFIX + key] = value
        end
      end

      def extract_from_rack(env)
        extract_from_text_map(env.reduce({}){|memo, (raw_header, value)|
          header = raw_header.to_s.gsub(/^HTTP_/, '').tr!('_', '-').downcase!

          memo[header] = value if header.start_with?(self.class::CARRIER_TRACER_STATE_PREFIX,
                                                     self.class::CARRIER_BAGGAGE_PREFIX)
          memo
        })
      end

      def trace_id_from_ctx(ctx)
        ctx.trace_id
      end
    end
  end
end
