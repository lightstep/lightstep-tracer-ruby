require 'bundler/setup'
require 'simplecov'
SimpleCov.command_name 'example.rb'
SimpleCov.start
require 'lightstep'

access_token = '{your_access_token}'

LightStep.configure(component_name: 'lightstep/ruby/example', access_token: access_token)

puts 'Starting operation...'
span = LightStep.start_span('my_span')
thread1 = Thread.new do
  for i in 1..10
    sleep(0.15)
    puts "Logging event #{i}..."
    span.log(event: 'hello world', count: i)
  end
end
thread2 = Thread.new do
  current = 1
  for i in 1..16
    child = LightStep.start_span('my_child', child_of: span)
    sleep(0.1)
    current *= 2
    child.log(event: "2^#{i}", result: current)
    child.finish
  end
end
[thread1, thread2].each(&:join)
span.finish
LightStep.flush
puts 'Done!'
puts "https://app.lightstep.com/#{access_token}/trace?span_guid=#{span.guid}&at_micros=#{span.start_micros}"
