module LightStep
  module Transport
    class Callback
      def initialize(callback:)
        @callback = callback
      end

      def flush_report(_auth, report)
        @callback.call(report)
        nil
      end

      def close(immediate)
      end
    end
  end
end
