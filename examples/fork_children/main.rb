# A simple, manual test ensuring that tracer instances still report after a
# Process.fork.

require 'bundler/setup'
require 'lightstep'

LightStep.configure(
  component_name: 'lightstep/ruby/examples/fork_children',
  access_token: '61c90a839a46c996e79c56afa1f116b8'
)

puts 'Starting...'
(1..20).each do |k|
  puts "Explicit reset iteration #{k}..."

  pid = Process.fork do
    10.times do
      span = LightStep.start_span("my_forked_span-#{Process.pid}")
      sleep(0.0025 * rand(k))
      span.finish
    end
    LightStep.flush
  end

  3.times do
    span = LightStep.start_span("my_process_span-#{Process.pid}")
    sleep(0.0025 * rand(k))
    span.set_tag(:empty, "")
    span.set_tag(:full, "full")
    span.finish
  end

  # Make sure redundant enable calls don't cause problems
  # NOTE: disabling discards the buffer by default, so all spans
  # get cleared here except the final toggle span
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
  Process.wait(pid)
end

puts 'Done!'

LightStep.flush
