require 'lightstep/tracer/client_tracer'

# TODO(ngauthier@gmail.com) this file should be lightstep.rb and only contain
# requires. Then break all code out into lightstep/tracer/tracer.rb as
# a singleton LightStep::Tracer class.
module LightStep
  module Tracer
    FORMAT_TEXT_MAP = 1
    FORMAT_BINARY = 2

    CARRIER_TRACER_STATE_PREFIX = 'ot-tracer-'.freeze
    CARRIER_BAGGAGE_PREFIX = 'ot-baggage-'.freeze
  end

  # TODO(ngauthier@gmail.com) singleton?
  # TODO(ngauthier@gmail.com) LightStep::Tracer as instance
  @@instance = nil

  def self.FORMAT_TEXT_MAP
    LightStep::Tracer::FORMAT_TEXT_MAP
  end

  def self.FORMAT_BINARY
    LightStep::Tracer::FORMAT_BINARY
  end

  def self.init_global_tracer(component_name, access_token, opts = nil)
    # FIXME(ngauthier@gmail.com) triple equals
    if component_name.class.name != 'String' || component_name.empty?
      puts "Invalid component_name: #{component_name}"
      exit(1)
      end

    # FIXME(ngauthier@gmail.com) triple equals
    if access_token.class.name != 'String' || access_token.empty?
      puts 'Invalid access_token'
      exit(1)
     end

    if @@instance.nil?
      opts = {} if opts.nil?
      @@instance = init_new_tracer(component_name, access_token, opts)
    else
      puts 'initGlobalTracer called multiple times'
      exit(1)
     end
    self
  end

  # Returns the singleton instance of the Tracer.
  def self.instance
    @@instance
   end

  # Creates a new tracer instance.
  #
  # @param $component_name Component name to use for the tracer
  # @param $access_token The project access token
  # @return LightStepBase_Tracer
  # @throws Exception if the group name or access token is not a valid string.
  def self.init_new_tracer(component_name, access_token, opts = nil)
    opts = {} if opts.nil?
    opts[:component_name] = component_name unless component_name.nil?
    opts[:access_token] = access_token unless access_token.nil?
    ClientTracer.new(opts)
   end

  def self.start_span(operation_name, fields = nil)
    instance.start_span(operation_name, fields)
  end

  # Moves the tracer into a disabled state: the reporting loop is immediately
  # stopped and spans finished or started in the disabled state will not be
  # reported.
  def self.disable
    instance.disable
  end

  # Reenables the tracer after a call to disable. This recreates the reporting
  # thread and it is again valid to start and finish new spans.
  def self.enable
    instance.enable
  end

  def self.flush
    instance.flush
   end
end
