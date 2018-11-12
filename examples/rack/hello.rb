# A very simple app test, to verify that a single span can be created and sent to LightStep
#
require 'bundler/setup'
require 'lightstep'
require 'rack'
require 'lightstep/transport/http_proto'
require 'rack/server'

access_token = '{your_access_token}'

LightStep.configure(
  component_name: 'lightstep/ruby/examples/helloWorld',
  access_token: access_token,
  transport: LightStep::Transport::HTTPPROTO.new(access_token: access_token),
)

span = LightStep.start_span('request')
span.log event: 'app', app: 'HelloWorld'
span.finish
LightStep.flush

puts 'Done!'
puts "https://app.lightstep.com/#{access_token}/trace?span_guid=#{span.span_context.id}&at_micros=#{span.start_micros}"
