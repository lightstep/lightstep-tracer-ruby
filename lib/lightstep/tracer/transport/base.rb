module LightStep
  module Transport
    class Base
      def initialize
      end

      def flush_report(_report)
        nil
      end

      def close(immediate)
      end
    end
  end
end
