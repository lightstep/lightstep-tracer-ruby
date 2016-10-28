require 'lightstep/tracer/transport/base'

module LightStep
  module Transport
    class Callback < Base
      def initialize(callback:)
        @callback = callback
      end

      def report(report)
        @callback.call(report)
        nil
      end

      def close
      end

      def clear
      end

      def flush
      end
    end
  end
end
