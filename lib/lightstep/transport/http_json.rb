require 'net/http'
require 'lightstep/transport/base'
require 'lightstep/auth'

module LightStep
  module Transport
    # HTTPJSON is a transport that sends reports via HTTP in JSON format.
    # It is thread-safe, however it is *not* fork-safe. When forking, all items
    # in the queue will be copied and sent in duplicate.
    #
    # When forking, you should first `disable` the tracer, then `enable` it from
    # within the fork (and in the parent post-fork). See
    # `examples/fork_children/main.rb` for an example.
    class HTTPJSON < Base
      LIGHTSTEP_HOST = 'collector.lightstep.com'.freeze
      LIGHTSTEP_PORT = 443

      ENCRYPTION_TLS = 'tls'.freeze
      ENCRYPTION_NONE = 'none'.freeze

      REPORTS_API_ENDPOINT = '/api/v0/reports'.freeze
      HEADER_ACCESS_TOKEN = 'LightStep-Access-Token'.freeze

      ##
      # Initialize the transport
      #
      # @param host [String] host of the domain to the endpoint to push data
      # @param port [Numeric] port on which to connect
      # @param verbose [Numeric] verbosity level. Right now 0-3 are supported
      # @param encryption [ENCRYPTION_TLS, ENCRYPTION_NONE] kind of encryption to use
      # @param access_token [String] access token for LightStep server
      # @param ssl_verify_peer [Boolean]
      # @param open_timeout [Integer]
      # @param read_timeout [Integer]
      # @param continue_timeout [Integer]
      # @param keep_alive_timeout [Integer]
      # @param logger [Logger]
      #
      def initialize(
        host: LIGHTSTEP_HOST,
        port: LIGHTSTEP_PORT,
        verbose: 0,
        encryption: ENCRYPTION_TLS,
        access_token:,
        ssl_verify_peer: true,
        open_timeout: 20,
        read_timeout: 20,
        continue_timeout: nil,
        keep_alive_timeout: 2,
        logger: nil
      )
        @host = host
        @port = port
        @verbose = verbose
        @encryption = encryption
        @ssl_verify_peer = ssl_verify_peer
        @open_timeout = open_timeout.to_i
        @read_timeout = read_timeout.to_i
        @continue_timeout = continue_timeout
        @keep_alive_timeout = keep_alive_timeout.to_i

        raise Tracer::ConfigurationError, 'access_token must be a string' unless access_token.is_a?(String)
        raise Tracer::ConfigurationError, 'access_token cannot be blank'  if access_token.empty?
        @auth = Auth.new(access_token)
        @logger = logger || LightStep.logger
      end

      ##
      # Queue a report for sending
      #
      def report(report)
        @logger.info report if @verbose >= 3

        req = build_request(report)
        res = connection.request(req)

        @logger.info res.to_s if @verbose >= 3

        nil
      end

      private

      ##
      # @param [Hash] report
      # @return [Net::HTTP::Post]
      #
      def build_request(report)
        req = Net::HTTP::Post.new(REPORTS_API_ENDPOINT)
        req[HEADER_ACCESS_TOKEN] = @auth.access_token
        req['Content-Type'] = 'application/json'
        req['Connection'] = 'keep-alive'
        req.body = report.to_json
        req
      end

      ##
      # @return [Net::HTTP]
      #
      def connection
        unless @connection
          @connection = ::Net::HTTP.new(@host, @port)
          @connection.use_ssl = @encryption == ENCRYPTION_TLS
          @connection.verify_mode = ::OpenSSL::SSL::VERIFY_NONE unless @ssl_verify_peer
          @connection.open_timeout = @open_timeout
          @connection.read_timeout = @read_timeout
          @connection.continue_timeout = @continue_timeout
          @connection.keep_alive_timeout = @keep_alive_timeout
        end
        @connection
      end
    end
  end
end
