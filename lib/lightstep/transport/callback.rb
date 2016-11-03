require 'lightstep/transport/base'

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
    end
  end
end
