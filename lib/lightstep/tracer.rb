require 'json'
require 'concurrent'

require 'lightstep/reporter'
require 'lightstep/transport/http_json'
require 'lightstep/transport/nil'
require 'lightstep/transport/callback'

module LightStep
  class Tracer
    class Error < LightStep::Error; end
    class ConfigurationError < LightStep::Tracer::Error; end

    attr_reader :access_token, :guid

    # Initialize a new tracer. Either an access_token or a transport must be
    # provided. A component_name is always required.
    # @param component_name [String] Component name to use for the tracer
    # @param access_token [String] The project access token when pushing to LightStep
    # @param transport [LightStep::Transport] How the data should be transported
    # @return LightStep::Tracer
    # @raise LightStep::ConfigurationError if the group name or access token is not a valid string.
    def initialize(component_name:, access_token: nil, transport: nil)
      configure(component_name: component_name, access_token: access_token, transport: transport)
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

    # TODO(ngauthier@gmail.com) inherit SpanContext from references

    # Starts a new span.
    # @param operation_name [String] the operation name for the Span
    # @param child_of [Span] Span to inherit from
    # @param start_time [Time] When the Span started, if not now
    # @param tags [Hash] tags for the span
    # @return [Span]
    def start_span(operation_name, child_of: nil, start_time: nil, tags: nil)
      child_of_id = nil
      trace_id = nil
      if OpenTracing::Span === child_of
        child_of_id = child_of.span_context.id
        trace_id = child_of.span_context.trace_id
      else
        trace_id = OpenTracing.guid
      end

      span = OpenTracing::Span.new(
        tracer: self,
        operation_name: operation_name,
        child_of_id: child_of_id,
        trace_id: trace_id,
        start_micros: start_time.nil? ? OpenTracing.micros(Time.now) : OpenTracing.micros(start_time),
        tags: tags,
        max_log_records: max_log_records
      )

      if OpenTracing::Span === child_of
        span.set_baggage(child_of.span_context.baggage)
      end

      span
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

    def configure(component_name:, access_token: nil, transport: nil)
      raise ConfigurationError, "component_name must be a string" unless String === component_name
      raise ConfigurationError, "component_name cannot be blank"  if component_name.empty?

      transport = Transport::HTTPJSON.new(access_token: access_token) if !access_token.nil?
      raise ConfigurationError, "you must provide an access token or a transport" if transport.nil?
      raise ConfigurationError, "#{transport} is not a LightStep transport class" if !(LightStep::Transport::Base === transport)

      @guid = OpenTracing.guid

      @reporter = LightStep::Reporter.new(
        max_span_records: max_span_records,
        transport: transport,
        guid: guid,
        component_name: component_name
      )
    end

    private
    DEFAULT_MAX_LOG_RECORDS = 1000
    MIN_MAX_LOG_RECORDS = 1
    DEFAULT_MAX_SPAN_RECORDS = 1000
    MIN_MAX_SPAN_RECORDS = 1
  end
end
