require 'bundler/setup'
require 'lightstep-tracer'

LightStep.configure(component_name: 'lightstep/ruby/example', access_token: '{your_access_token}')

puts 'Starting...'

mutex = Mutex.new
done = false
span_count = 0
percent_done = 0
total_time = 0

watchThread = Thread.new do
  loop do
    sleep(0.5)
    mutex.lock
    time_per_span = (1e6 * (total_time.to_f / span_count.to_f)).round(2)
    puts "#{span_count} spans #{percent_done}% done #{total_time.round(2)} seconds (#{time_per_span} us/span)"
    is_done = done
    mutex.unlock
    Thread.exit if is_done
  end
end

thread = Thread.new do
  count = 0
  total_time = 0
  for j in 1..1000
    start = Time.now
    for i in 1..100
      span = LightStep.start_span('my_span')
      span.log_event('hello world', count: i)
      span.finish
      count += 1
    end
    delta = Time.now - start

    mutex.lock
    percent_done = (100.0 * (count / 100_000.0)).ceil
    span_count = count
    total_time += delta
    mutex.unlock
  end
end

thread.join
mutex.lock
done = true
mutex.unlock
watchThread.join

puts 'Done!'
