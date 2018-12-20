# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'lightstep/version'

Gem::Specification.new do |spec|
  spec.name          = 'lightstep'
  spec.version       = LightStep::VERSION
  spec.authors       = ['lightstep']
  spec.email         = ['support@lightstep.com']

  spec.summary       = 'LightStep OpenTracing Ruby bindings'
  spec.homepage      = 'https://github.com/lightstep/lightstep-tracer-ruby'
  spec.license       = 'MIT'

  spec.files         = `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  spec.require_paths = ['lib']

  spec.metadata    = {
    "changelog_uri" => "https://github.com/lightstep/lightstep-tracer-ruby/blob/master/CHANGELOG.md",
  }

  spec.add_dependency 'concurrent-ruby', '~> 1.0'
  spec.add_dependency 'opentracing', '~> 0.4.1'
  spec.add_development_dependency 'rake', '~> 11.3'
  spec.add_development_dependency 'rack', '~> 2.0'
  spec.add_development_dependency 'rspec', '~> 3.0'
  spec.add_development_dependency 'bump', '~> 0.5'
  spec.add_development_dependency 'simplecov', '~> 0.16'
  spec.add_development_dependency 'timecop', '~> 0.8.0'
end
