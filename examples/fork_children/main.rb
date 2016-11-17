# A simple, manual test ensuring that tracer instances still report after a
# Process.fork.

require 'bundler/setup'
require 'lightstep'
require 'opentracing'

tracer = LightStep::Tracer.new(
  component_name: 'lightstep/ruby/examples/fork_children',
  access_token: '{your_access_token}'
)

puts 'Starting...'
(1..20).each do |k|
  puts "Explicit reset iteration #{k}..."

  pid = Process.fork do
    10.times do
      span = tracer.start_span("my_forked_span-#{Process.pid}")
      sleep(0.0025 * rand(k))
      span.finish
    end
    tracer.flush
  end

  10.times do
    span = tracer.start_span("my_process_span-#{Process.pid}")
    sleep(0.0025 * rand(k))
    span.finish
  end

  # Make sure redundant enable calls don't cause problems
  # NOTE: disabling discards the buffer by default, so all spans
  # get cleared here except the final toggle span
  10.times do
    tracer.disable
    tracer.enable
    tracer.disable
    tracer.disable
    tracer.enable
    tracer.enable
    span = tracer.start_span("my_toggle_span-#{Process.pid}")
    sleep(0.0025 * rand(k))
    span.finish
  end

  puts "Parent, pid #{Process.pid}, waiting on child pid #{pid}"
  Process.wait(pid)
end

puts 'Done!'

tracer.flush
