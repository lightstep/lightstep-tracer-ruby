require 'json'
require 'concurrent'

require 'opentracing'

require 'lightstep/span'
require 'lightstep/reporter'
require 'lightstep/propagation'
require 'lightstep/transport/http_json'
require 'lightstep/transport/nil'
require 'lightstep/transport/callback'

module LightStep
  class Tracer
    class Error < LightStep::Error; end
    class ConfigurationError < LightStep::Tracer::Error; end

    DEFAULT_MAX_LOG_RECORDS = 1000
    MIN_MAX_LOG_RECORDS = 1
    DEFAULT_MAX_SPAN_RECORDS = 1000
    MIN_MAX_SPAN_RECORDS = 1

    attr_reader :access_token, :guid

    # Initialize a new tracer. Either an access_token or a transport must be
    # provided. A component_name is always required.
    # @param component_name [String] Component name to use for the tracer
    # @param access_token [String] The project access token when pushing to LightStep
    # @param transport [LightStep::Transport] How the data should be transported
    # @param tags [Hash] Tracer-level tags
    # @param propagator [Propagator] Symbol one of :lightstep, :b3 indicating the propagator
    #   to use
    # @return LightStep::Tracer
    # @raise LightStep::ConfigurationError if the group name or access token is not a valid string.
    def initialize(component_name:,
                   access_token: nil,
                   transport: nil,
                   tags: {},
                   propagator: :lightstep)
      configure(component_name: component_name,
                access_token: access_token,
                transport: transport,
                tags: tags,
                propagator: propagator)
    end

    def max_log_records
      @max_log_records ||= DEFAULT_MAX_LOG_RECORDS
    end

    def max_log_records=(max)
      @max_log_records = [MIN_MAX_LOG_RECORDS, max].max
    end

    def max_span_records
      @max_span_records ||= DEFAULT_MAX_SPAN_RECORDS
    end

    def max_span_records=(max)
      @max_span_records = [MIN_MAX_SPAN_RECORDS, max].max
      @reporter.max_span_records = @max_span_records
    end

    # Set the report flushing period. If set to 0, no flushing will be done, you
    # must manually call flush.
    def report_period_seconds=(seconds)
      @reporter.period = seconds
    end

    # TODO(bhs): Support FollowsFrom and multiple references

    # Creates a scope manager or returns the already-created one.
    #
    # @return [ScopeManager] the current ScopeManager, which may be a no-op but
    #   may not be nil.
    def scope_manager
      @scope_manager ||= LightStep::ScopeManager.new
    end

    # Returns a newly started and activated Scope.
    #
    # If ScopeManager#active is not nil, no explicit references are provided,
    # and `ignore_active_scope` is false, then an inferred References#CHILD_OF
    # reference is created to the ScopeManager#active's SpanContext when
    # start_active_span is invoked.
    #
    # @param operation_name [String] The operation name for the Span
    # @param child_of [SpanContext, Span] SpanContext that acts as a parent to
    #        the newly-started Span. If a Span instance is provided, its
    #        context is automatically substituted. See [Reference] for more
    #        information.
    #
    #   If specified, the `references` parameter must be omitted.
    # @param references [Array<Reference>] An array of reference
    #   objects that identify one or more parent SpanContexts.
    # @param start_time [Time] When the Span started, if not now
    # @param tags [Hash] Tags to assign to the Span at start time
    # @param ignore_active_scope [Boolean] whether to create an implicit
    #   References#CHILD_OF reference to the ScopeManager#active.
    # @param finish_on_close [Boolean] whether span should automatically be
    #   finished when Scope#close is called
    # @yield [Scope] If an optional block is passed to start_active_span it will
    #   yield the newly-started Scope. If `finish_on_close` is true then the
    #   Span will be finished automatically after the block is executed.
    # @return [Scope, Object] If passed an optional block, start_active_span
    #   returns the block's return value, otherwise it returns the newly-started
    #   and activated Scope
    def start_active_span(operation_name,
                          child_of: nil,
                          references: nil,
                          start_time: Time.now,
                          tags: nil,
                          ignore_active_scope: false,
                          finish_on_close: true)
      if child_of.nil? && references.nil? && !ignore_active_scope
        child_of = active_span
      end

      span = start_span(
        operation_name,
        child_of: child_of,
        references: references,
        start_time: start_time,
        tags: tags,
        ignore_active_scope: ignore_active_scope
      )

      scope_manager.activate(span: span, finish_on_close: finish_on_close).tap do |scope|
        if block_given?
          begin
            return yield scope
          ensure
            scope.close
          end
        end
      end
    end

    # Returns the span from the active scope, if any.
    #
    # @return [Span, nil] the active span. This is a shorthand for
    #   `scope_manager.active.span`, and nil will be returned if
    #   Scope#active is nil.
    def active_span
      scope = scope_manager.active
      scope.span if scope
    end

    # Starts a new span.
    #
    # @param operation_name [String] The operation name for the Span
    # @param child_of [SpanContext] SpanContext that acts as a parent to
    #        the newly-started Span. If a Span instance is provided, its
    #        .span_context is automatically substituted.
    # @param references [Array<SpanContext>] An array of SpanContexts that
    #         identify any parent SpanContexts of newly-started Span. If Spans
    #         are provided, their .span_context is automatically substituted.
    # @param start_time [Time] When the Span started, if not now
    # @param tags [Hash] Tags to assign to the Span at start time
    # @param ignore_active_scope [Boolean] whether to create an implicit
    #   References#CHILD_OF reference to the ScopeManager#active.
    # @yield [Span] If passed an optional block, start_span will yield the
    #   newly-created span to the block. The span will be finished automatically
    #   after the block is executed.
    # @return [Span, Object] If passed an optional block, start_span will return
    #  the block's return value, otherwise it returns the newly-started Span
    #  instance, which has not been automatically registered via the
    #  ScopeManager
    def start_span(operation_name, child_of: nil, references: nil, start_time: nil, tags: nil, ignore_active_scope: false)
      if child_of.nil? && references.nil? && !ignore_active_scope
        child_of = active_span
      end

      span_options = {
        tracer: self,
        operation_name: operation_name,
        child_of: child_of,
        references: references,
        start_micros: start_time.nil? ? LightStep.micros(Time.now) : LightStep.micros(start_time),
        tags: tags,
        max_log_records: max_log_records,
      }

      Span.new(span_options).tap do |span|
        if block_given?
          begin
            return yield span
          ensure
            span.finish
          end
        end
      end
    end


    # Inject a SpanContext into the given carrier
    #
    # @param spancontext [SpanContext]
    # @param format [OpenTracing::FORMAT_TEXT_MAP, OpenTracing::FORMAT_BINARY]
    # @param carrier [Carrier] A carrier object of the type dictated by the specified `format`
    def inject(span_context, format, carrier)
      @propagator.inject(span_context, format, carrier)
    end

    # Extract a SpanContext from a carrier
    # @param format [OpenTracing::FORMAT_TEXT_MAP, OpenTracing::FORMAT_BINARY, OpenTracing::FORMAT_RACK]
    # @param carrier [Carrier] A carrier object of the type dictated by the specified `format`
    # @return [SpanContext] the extracted SpanContext or nil if none could be found
    def extract(format, carrier)
      @propagator.extract(format, carrier)
    end

    # @return true if the tracer is enabled
    def enabled?
      return @enabled if defined?(@enabled)
      @enabled = true
    end

    # Enables the tracer
    def enable
      @enabled = true
    end

    # Disables the tracer
    # @param discard [Boolean] whether to discard queued data
    def disable(discard: true)
      @enabled = false
      @reporter.clear if discard
      @reporter.flush
    end

    # Flush to the Transport
    def flush
      return unless enabled?
      @reporter.flush
    end

    # Internal use only.
    # @private
    def finish_span(span)
      return unless enabled?
      @reporter.add_span(span)
    end

    protected

    def configure(component_name:,
                  access_token: nil,
                  transport: nil, tags: {},
                  propagator: :lightstep)

      raise ConfigurationError, "component_name must be a string" unless component_name.is_a?(String)
      raise ConfigurationError, "component_name cannot be blank"  if component_name.empty?

      if transport.nil? and !access_token.nil?
        transport = Transport::HTTPJSON.new(access_token: access_token)
      end

      raise ConfigurationError, "you must provide an access token or a transport" if transport.nil?
      raise ConfigurationError, "#{transport} is not a LightStep transport class" if !(LightStep::Transport::Base === transport)

      @propagator = Propagation[propagator]

      @guid = LightStep.guid

      @reporter = LightStep::Reporter.new(
        max_span_records: max_span_records,
        transport: transport,
        guid: guid,
        component_name: component_name,
        tags: tags
      )
    end
  end
end
