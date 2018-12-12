require 'json'
require 'base64'
require 'opentracing'
require 'bundler/setup'
require 'simplecov'
SimpleCov.start
require 'lightstep'


tracer = LightStep::Tracer.new(access_token: "invalid", component_name: "test")

body = JSON.parse(STDIN.read)
span_context = tracer.extract(OpenTracing::FORMAT_TEXT_MAP, body['text_map'])

new_text_map = Hash.new
tracer.inject(span_context, OpenTracing::FORMAT_TEXT_MAP, new_text_map)

STDOUT.write JSON.generate({"text_map"=> new_text_map})

