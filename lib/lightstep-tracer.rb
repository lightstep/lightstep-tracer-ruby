require 'lightstep/tracer/tracer'
require 'lightstep/tracer/global_tracer'

# TODO(ngauthier@gmail.com) this file should be lightstep.rb and only contain
# requires. Then break all code out into lightstep/tracer/tracer.rb as
# a singleton LightStep::Tracer class.
module LightStep

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

  # TODO(ngauthier@gmail.com) delegate with forwardable
  def self.configure(component_name, access_token, opts = {})
   instance.configure({component_name: component_name, access_token: access_token}.merge(opts))
  end

  # TODO(ngauthier@gmail.com) delegate with forwardable
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
