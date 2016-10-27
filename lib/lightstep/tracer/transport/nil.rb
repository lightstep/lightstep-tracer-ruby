module LightStep
  module Transport
    # Empty transport, primarily for unit testing purposes
    class Nil
      def initialize
      end

      def flush_report(_auth, _report)
        nil
      end

      def close(immediate)
      end
    end
  end
end
