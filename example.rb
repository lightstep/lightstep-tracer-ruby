require './lightstep.rb'

LightStep.initGlobalTracer('lightstep/ruby/example', '{your_access_token}')

span = LightStep.instance.startSpan('my_span')
span.logEvent('hello world', { 'count' => 42 })
span.finish()
