require 'forwardable'
require 'lightstep/tracer/tracer'
require 'lightstep/tracer/global_tracer'

module LightStep
  extend SingleForwardable

  def self.FORMAT_TEXT_MAP
    LightStep::Tracer::FORMAT_TEXT_MAP
  end

  def self.FORMAT_BINARY
    LightStep::Tracer::FORMAT_BINARY
  end

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
