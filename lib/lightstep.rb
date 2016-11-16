require 'forwardable'
require 'opentracing'

# LightStep Tracer
module LightStep
  # Base class for all LightStep errors
  class Error < StandardError; end
end

require 'lightstep/tracer'
