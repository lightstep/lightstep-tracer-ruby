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

  # Convert a time to microseconds
  def self.micros(time)
    (time.to_f * 1E6).floor
  end

  # Returns a random guid. Note: this intentionally does not use SecureRandom,
  # which is slower and cryptographically secure randomness is not required here.
  def self.guid
    unless @_lastpid == Process.pid
      @_lastpid = Process.pid
      @_rng = Random.new
    end
    @_rng.bytes(8).unpack('H*')[0]
  end
end

require 'lightstep/tracer'
require 'lightstep/global_tracer'
