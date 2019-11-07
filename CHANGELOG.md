# Changelog
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## v0.15.1
### Fixed
- The tracer now supports B3 context propagation. Propagation can be set by using the `propagator` keyword argument to `LightStep.configure`. Valid values are `:lightstep` (default), and `:b3`.
- The tracer now closes the active scope or finishes the active span even if an error is raised from the yielded code.

### Unreleased
- In-progress B3 support

## v0.15.0
### Added
- A Changelog
- Now supports Span#log_kv
- Updated to opentracing-ruby 0.5.0
- Now delegates Lightstep#active_span to the tracer
- Now supports passing a block to #start_span
- The block forms of #start_span and #start active_span now return the result of executing the block

### Changed
- Tracer#extract now supports symbols in carrier

### Deprecated
- Span#log (reflecting deprecation in opentracing 0.4.0)

### Removed

### Fixed
- Fix handling of non-string tag values in `start_span`.

### Security

