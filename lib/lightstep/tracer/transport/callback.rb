require 'lightstep/tracer/transport/base'

module LightStep
  module Transport
    class Callback < Base
      def initialize(callback:)
        @callback = callback
      end

      def flush_report(report)
        @callback.call(report)
        nil
      end

      def close(immediate)
      end
    end
  end
end
