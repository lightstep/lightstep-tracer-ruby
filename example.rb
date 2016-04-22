require_relative './lib/lightstep-tracer.rb'

LightStep.init_global_tracer('lightstep/ruby/example', '{your_access_token}', {
                               #:collector_host => 'localhost',
                               #:collector_port => 9998,
                               #:collector_encryption => 'none',
                             })

puts 'Starting operation...'
span = LightStep.start_span('my_span')
thread1 = Thread.new do
  for i in 1..10
    sleep(0.8)
    puts "Logging event #{i}..."
    span.log_event('hello world', count: i)
  end
end
thread2 = Thread.new do
  current = 1
  for i in 1..16
    child = LightStep.start_span('my_child', parent: span)
    sleep(0.2)
    current *= 2
    child.log_event("2^#{i}", result: current)
    child.finish
  end
end
[thread1, thread2].each(&:join)
span.finish

puts 'Done!'
puts span.generate_trace_url
