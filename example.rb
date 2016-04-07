require './lightstep.rb'

LightStep.init_global_tracer('lightstep/ruby/example', '{your_access_token}', {
    :collector_host => 'localhost',
    :collector_port => 9998,
    :collector_encryption => 'none',
})

span = LightStep.start_span('my_span')
span.log_event('hello world', { 'count' => 42 })
span.finish()

LightStep.instance.flush()
puts 'Done!'
