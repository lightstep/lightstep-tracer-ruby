# lightstep-tracer-ruby [Deprecated]

> ❗ **This instrumentation is no longer recommended**. Please review [documentation on setting up and configuring the OpenTelemetry Ruby API and SDK, and related gems](https://github.com/open-telemetry/opentelemetry-ruby) for more information.

In August 2023, [Lightstep became ServiceNow
Cloud Observability](https://docs.lightstep.com/docs/banner-faq). To ease the
transition, all code artifacts will continue to use the Lightstep name. You
don't need to do anything to keep using this repository.

[![Gem Version](https://badge.fury.io/rb/lightstep.svg)](https://badge.fury.io/rb/lightstep) [![Circle CI](https://circleci.com/gh/lightstep/lightstep-tracer-ruby.svg?style=shield)](https://circleci.com/gh/lightstep/lightstep-tracer-ruby) [![MIT license](http://img.shields.io/badge/license-MIT-blue.svg)](http://opensource.org/licenses/MIT) [![Code Climate](https://codeclimate.com/github/lightstep/lightstep-tracer-ruby/badges/gpa.svg)](https://codeclimate.com/github/lightstep/lightstep-tracer-ruby)

The LightStep distributed tracing library for Ruby.

## Installation

Add this line to your application's Gemfile:

    gem 'lightstep'


And then execute:

    $ bundle

Or install it yourself as:

    $ gem install lightstep


## Getting started

    require 'lightstep'

    # Initialize the singleton tracer
    LightStep.configure(component_name: 'lightstep/ruby/example', access_token: 'your_access_token')

    # Specify a propagation format (options are :lightstep (default) and :b3)
    LightStep.configure(component_name: 'lightstep/ruby/example', access_token: 'your_access_token', propagator: :b3)

    # Create a basic span and attach a log to the span
    span = LightStep.start_span('my_span')
    span.log(event: 'hello world', count: 42)

    # Create a child span (and add some artificial delays to illustrate the timing)
    sleep(0.1)
    child = LightStep.start_span('my_child', child_of: span.span_context)
    sleep(0.2)
    child.finish
    sleep(0.1)
    span.finish

## Thread Safety

The LightStep Tracer is threadsafe. For increased performance, you can add the
`concurrent-ruby-ext` gem to your Gemfile. This will enable C extensions for
concurrent operations.

The LightStep Tracer is also Fork-safe. When forking, the child process will
not inherit the unflushed spans of the parent, so they will only be flushed
once.

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `make test` to run the tests.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).
