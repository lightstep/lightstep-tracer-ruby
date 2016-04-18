require_relative './lightstep/tracer/thrift/types'
require_relative './lightstep/tracer/client_tracer'

module LightStep
  @@instance = nil

  # Initializes and returns the singleton instance of the Tracer.
  # For convenience, multiple calls to initialize are allowed. For example,
  # in library code with more than possible first entry-point, this may
  # be helpful.
  #
  # @return LightStepBase_Tracer
  # @throws Exception if the component name or access token is not a valid string
  # @throws Exception if the tracer singleton has already been initialized
  def self.init_global_tracer(component_name, access_token, opts = nil)
    if component_name.class.name != 'String' || component_name.empty?
      puts "Invalid component_name: #{component_name}"
      exit(1)
      end

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

  def self.flush
    instance.flush
   end
end
