require 'bundler/setup'
require 'lightstep'
require 'opentracing'

require 'rack'
require 'rack/server'

OpenTracing.global_tracer = LightStep::Tracer.new(
  component_name: 'lightstep/ruby/examples/rack',
  access_token: '{your_access_token}'
)

class HelloWorldApp
  def self.call(env)
    span = OpenTracing.start_span('request')
    span.log event: 'env', env: env
    resp = [200, {}, ["Hello World. You said: #{env['QUERY_STRING']}"]]
    span.finish
    resp
  end
end

Rack::Server.start app: HelloWorldApp
