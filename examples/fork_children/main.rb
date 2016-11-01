# A simple, manual test ensuring that tracer instances still report after a
# Process.fork. Currently this requires the tracer instance to be explicitly
# disabled before the fork and reenabled afterward.

require 'bundler/setup'
require 'lightstep'

LightStep.configure(
  component_name: 'lightstep/ruby/examples/fork_children',
  access_token: '{your_access_token}'
)

puts 'Starting...'
(1..20).each do |k|
  puts "Explicit reset iteration #{k}..."

  # NOTE: the tracer is disabled and reenabled on either side of the fork
  LightStep.disable
  pid = Process.fork do
    LightStep.enable
    10.times do
      span = LightStep.start_span("my_forked_span-#{Process.pid}")
      sleep(0.0025 * rand(k))
      span.finish
    end
  end

  # Also renable the parent process' tracer
  LightStep.enable

  10.times do
    span = LightStep.start_span("my_process_span-#{Process.pid}")
    sleep(0.0025 * rand(k))
    span.finish
  end

  # Make sure redundant enable calls don't cause problems
  10.times do
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

puts 'Done!'
