.PHONY: build test publish

build:
	gem build lightstep-tracer.gemspec

test:
	rake spec

publish: build test
	gem bump --version patch
	make build	# rebuild after version increment
	git tag `ruby scripts/version.rb`
	git push
	git push --tags
	gem push lightstep-tracer-`ruby scripts/version.rb`.gem
