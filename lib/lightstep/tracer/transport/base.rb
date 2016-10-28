module LightStep
  module Transport
    class Base
      def initialize
      end

      def report(_report)
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
