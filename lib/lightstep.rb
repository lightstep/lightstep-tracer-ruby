require 'forwardable'

# LightStep Tracer
module LightStep
  extend SingleForwardable

  # Base class for all LightStep errors
  class Error < StandardError; end

  # Returns the singleton instance of the Tracer.
  def self.instance
    LightStep::GlobalTracer.instance
  end

  def_delegator :instance, :configure
  def_delegator :instance, :start_span
  def_delegator :instance, :disable
  def_delegator :instance, :enable
  def_delegator :instance, :flush
end

require 'lightstep/tracer'
require 'lightstep/global_tracer'
