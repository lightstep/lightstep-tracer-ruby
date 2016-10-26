# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'lightstep/tracer/version'

Gem::Specification.new do |spec|
  spec.name          = 'lightstep-tracer'
  spec.version       = Lightstep::Tracer::VERSION
  spec.authors       = ['bcronin']
  spec.email         = ['support@lightstep.com']

  spec.summary       = 'LightStep OpenTracing Ruby bindings'
  spec.homepage      = 'https://github.com/lightstep/lightstep-tracer-ruby'
  spec.license       = 'MIT'

  spec.files         = `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  spec.require_paths = ['lib']

  spec.add_development_dependency 'rake', '~> 10.0'
  spec.add_development_dependency 'rspec', '~> 3.0'
  spec.add_development_dependency 'bump', '~> 0.5'
  spec.add_development_dependency 'simplecov', '~> 0.12.0'
end
