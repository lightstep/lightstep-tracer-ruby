module LightStep
  module Transport
    # Base Transport type
    class Base
      def initialize
      end

      def report(_report)
        nil
      end
    end
  end
end
