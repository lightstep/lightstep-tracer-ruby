.PHONY: build test benchmark publish

build:
	gem build lightstep-tracer.gemspec

test:
	rake spec
	ruby example.rb

benchmark:
	ruby benchmark/bench.rb
	ruby benchmark/threading/thread_test.rb

publish: build test benchmark
	ruby -e 'require "bump"; Bump::Bump.run("patch")'
	make build	# rebuild after version increment
	git tag `ruby scripts/version.rb`
	git push
	git push --tags
	gem push lightstep-tracer-`ruby scripts/version.rb`.gem

# An internal LightStep target for regenerating the thrift protocol files
.PHONY: thrift
thrift:
	thrift -r -gen rb -out lib/lightstep/tracer/thrift $(LIGHTSTEP_HOME)/go/src/crouton/crouton.thrift
	rm lib/lightstep/tracer/thrift/reporting_service.rb
	rm lib/lightstep/tracer/thrift/crouton_constants.rb
	ruby scripts/patch_thrift.rb
