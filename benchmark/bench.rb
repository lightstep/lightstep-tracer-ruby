require 'benchmark'
require 'securerandom'

require_relative '../lib/lightstep-tracer.rb'

rng = Random.new

# Run a quick profile on logging lots of spans
tracer = LightStep.init_new_tracer('lightstep/ruby/spec', '{your_access_token}')

Benchmark.bm(32) do |x|
  x.report('Random.bytes.unpack') do
    for i in 1..10_000; rng.bytes(8).unpack('H*'); end
  end
  x.report('Random.bytes.each_byte.map') do
    for i in 1..10_000; rng.bytes(8).each_byte.map { |b| b.to_s(16) }.join; end
  end
  x.report('SecureRandom.hex') do
    for i in 1..10_000; SecureRandom.hex(8); end
  end

  x.report('start_span(1000)') do
    for i in 0..1000
      span = tracer.start_span('my_span')
      span.finish
    end
  end
end
