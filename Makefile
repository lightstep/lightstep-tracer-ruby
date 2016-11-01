.PHONY: build test benchmark publish

build:
	gem build lightstep-tracer.gemspec

test:
	bundle exec rake spec
	ruby example.rb
	ruby examples/fork_children/main.rb

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
