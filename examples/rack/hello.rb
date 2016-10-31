require 'bundler/setup'
require 'lightstep'

require 'rack'
require 'rack/server'

LightStep.configure(
  component_name: 'lightstep/ruby/examples/rack',
  access_token: '{your_access_token}'
)

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
