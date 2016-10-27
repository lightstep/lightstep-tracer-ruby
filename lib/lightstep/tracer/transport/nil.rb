require 'lightstep/tracer/transport/base'

module LightStep
  module Transport
    # Empty transport, primarily for unit testing purposes
    class Nil < Base
    end
  end
end
