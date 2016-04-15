# lightstep-tracer-ruby

[![Circle CI](https://circleci.com/gh/lightstep/lightstep-tracer-ruby.svg?style=shield)](https://circleci.com/gh/lightstep/lightstep-tracer-ruby)

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'lightstep-tracer'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install lightstep-tracer


## Getting started

```ruby
require 'lightstep-tracer'

# Initialize the singleton tracer
LightStep.init_global_tracer('lightstep/ruby/example', '{your_access_token}')

# Create a basic span and attach a log to the span
span = LightStep.start_span('my_span')
span.log_event('hello world', { 'count' => 42 })

# Create a child span (and add some artificial delays to illustrate the timing)
sleep(0.1)
child = LightStep.start_span('my_child', { :parent => span, })
sleep(0.2)
child.finish()
sleep(0.1)
span.finish()

# Flush any enqueued data before program exit
LightStep.instance.flush()
```

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `make test` to run the tests.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## License

The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).
