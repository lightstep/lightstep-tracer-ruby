require './lib/lightstep/tracer/thrift/types'
require './lib/lightstep/tracer/client_tracer'

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
		if component_name.class.name != "String" || component_name.size == 0
        	puts "Invalid component_name: #{component_name}"
        	exit(1)
    	end

    	if access_token.class.name != "String" || access_token.size == 0
    		puts "Invalid access_token"
    		exit(1)
    	end

    	if @@instance.nil?
			if opts.nil?
				opts = {}
			end
    		@@instance = self.init_new_tracer(component_name, access_token, opts)
    	else
			puts "initGlobalTracer called multiple times"
			exit(1)
    	end
    	self
	end

	# Returns the singleton instance of the Tracer.
  	def self.instance()
		return @@instance
	end

 	# Creates a new tracer instance.
	#
  	# @param $component_name Component name to use for the tracer
	# @param $access_token The project access token
	# @return LightStepBase_Tracer
	# @throws Exception if the group name or access token is not a valid string.
  	def self.init_new_tracer(component_name, access_token, opts = nil)
  		if (opts.nil?)
      		opts = {}
    	end
    	unless (component_name.nil?)
      		opts[:component_name] = component_name
    	end
    	unless (access_token.nil?)
      		opts[:access_token] = access_token
    	end
    	ClientTracer.new(opts)
  	end

	def self.start_span(operation_name, fields = nil)
		self.instance.start_span(operation_name, fields)
	end

  	def self.flush
		self.instance.flush
  	end
end
