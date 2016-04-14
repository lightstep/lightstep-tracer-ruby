.PHONY: build test publish

build:
	gem build lightstep-tracer.gemspec

test:
	rake spec

publish: build test
	gem push lightstep-tracer-$(shell ruby scripts/version.rb).gem
