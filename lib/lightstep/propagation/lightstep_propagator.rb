#frozen_string_literal: true

module LightStep
  module Propagation
    class LightStepPropagator
      CARRIER_TRACER_STATE_PREFIX = 'ot-tracer-'.freeze
      CARRIER_BAGGAGE_PREFIX = 'ot-baggage-'.freeze
      CARRIER_SPAN_ID = (CARRIER_TRACER_STATE_PREFIX + 'spanid').freeze
      CARRIER_TRACE_ID = (CARRIER_TRACER_STATE_PREFIX + 'traceid').freeze
      CARRIER_SAMPLED = (CARRIER_TRACER_STATE_PREFIX + 'sampled').freeze

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
        carrier[CARRIER_SPAN_ID] = span_context.id
        carrier[CARRIER_TRACE_ID] = span_context.trace_id unless span_context.trace_id.nil?
        carrier[CARRIER_SAMPLED] = 'true'

        span_context.baggage.each do |key, value|
          carrier[CARRIER_BAGGAGE_PREFIX + key] = value
        end
      end

      def extract_from_text_map(carrier)
        # If the carrier does not have both the span_id and trace_id key
        # skip the processing and just return a normal span
        if !carrier.has_key?(CARRIER_SPAN_ID) || !carrier.has_key?(CARRIER_TRACE_ID)
          return nil
        end

        baggage = carrier.reduce({}) do |baggage, tuple|
          key, value = tuple
          if key.start_with?(CARRIER_BAGGAGE_PREFIX)
            plain_key = key.to_s[CARRIER_BAGGAGE_PREFIX.length..key.to_s.length]
            baggage[plain_key] = value
          end
          baggage
        end
        SpanContext.new(
          id: carrier[CARRIER_SPAN_ID],
          trace_id: carrier[CARRIER_TRACE_ID],
          baggage: baggage,
        )
      end

      def inject_to_rack(span_context, carrier)
        carrier[CARRIER_SPAN_ID] = span_context.id
        carrier[CARRIER_TRACE_ID] = span_context.trace_id unless span_context.trace_id.nil?
        carrier[CARRIER_SAMPLED] = 'true'

        span_context.baggage.each do |key, value|
          if key =~ /[^A-Za-z0-9\-_]/
            # TODO: log the error internally
            next
          end
          carrier[CARRIER_BAGGAGE_PREFIX + key] = value
        end
      end

      def extract_from_rack(env)
        extract_from_text_map(env.reduce({}){|memo, tuple|
          raw_header, value = tuple
          header = raw_header.to_s.gsub(/^HTTP_/, '').tr('_', '-').downcase

          memo[header] = value if header.start_with?(CARRIER_TRACER_STATE_PREFIX, CARRIER_BAGGAGE_PREFIX)
          memo
        })
      end
    end
  end
end
