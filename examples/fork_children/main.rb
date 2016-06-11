# A simple, manual test ensuring that tracer instances still report after a Process.fork.
# Currently this requires the tracer instance to be explicitly disabled before the fork
# and reenabled afterward.
#
require_relative '../../lib/lightstep-tracer.rb'
require 'thread'

LightStep.init_global_tracer('lightstep/ruby/examples/fork_children', '{your_access_token}')

puts 'Starting...'
for k in 1..20
  puts "Iteration #{k}..."

  # NOTE: the tracer is disabled and reenalbed on either side of the fork
  LightStep.disable
  pid = Process.fork do
    LightStep.enable

    puts "Child, pid #{Process.pid}"
    for i in 1..10
      span = LightStep.start_span("my_forked_span-#{Process.pid}")
      sleep(0.0025 * rand(k))
      span.finish
    end
    puts 'Child done'
  end

  # Also renable the parent process' tracer
  LightStep.enable

  for i in 1..10
    span = LightStep.start_span("my_process_span-#{Process.pid}")
    sleep(0.0025 * rand(k))
    span.finish
  end

  # Make sure redundant enable calls don't cause problems
  for i in 1..10
    LightStep.disable
    LightStep.enable
    LightStep.disable
    LightStep.disable
    LightStep.enable
    LightStep.enable
    span = LightStep.start_span("my_toggle_span-#{Process.pid}")
    sleep(0.0025 * rand(k))
    span.finish
  end

  puts "Parent, pid #{Process.pid}, waiting on child pid #{pid}"
  Process.wait
end

puts 'Exiting'
