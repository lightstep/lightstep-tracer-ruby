require_relative '../../lib/lightstep-tracer.rb'

require 'rack'
require 'rack/server'

LightStep.init_global_tracer('lightstep/ruby/examples/rack', '{your_access_token}')

class HelloWorldApp
  def self.call(env)
    span = LightStep.start_span('request')
    span.log_event 'env', env
    resp = [200, {}, ["Hello World. You said: #{env['QUERY_STRING']}"]]
    span.finish
    resp
  end
end

Rack::Server.start app: HelloWorldApp
