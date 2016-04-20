require 'benchmark'
require 'securerandom'

require_relative '../lib/lightstep-tracer.rb'

rng = Random.new

# Run a quick profile on logging lots of spans
tracer = LightStep.init_new_tracer('lightstep/ruby/spec', '{your_access_token}', transport: 'nil')

Benchmark.bm(32) do |x|
  x.report('Random.bytes.unpack') do
    for i in 1..10_000; rng.bytes(8).unpack('H*')[0]; end
  end
  x.report('Random.bytes.each_byte.map') do
    for i in 1..10_000; rng.bytes(8).each_byte.map { |b| b.to_s(16) }.join; end
  end
  x.report('SecureRandom.hex') do
    for i in 1..10_000; SecureRandom.hex(8); end
  end

  x.report('start_span(100)') do
    for i in 0..100; tracer.start_span('my_span').finish; end
  end
  x.report('start_span(1000)') do
    for i in 0..1000; tracer.start_span('my_span').finish; end
  end
  x.report('start_span(10000)') do
    for i in 0..10_000; tracer.start_span('my_span').finish; end
  end

  x.report('log_event(100)') do
    span = tracer.start_span('my_span')
    for i in 0..100; span.log_event('event', i); end
    span.finish
  end
  x.report('log_event(1000)') do
    span = tracer.start_span('my_span')
    for i in 0..1000; span.log_event('event', i); end
    span.finish
  end
  x.report('log_event(10000)') do
    span = tracer.start_span('my_span')
    for i in 0..10_000; span.log_event('event', i); end
    span.finish
  end
end
