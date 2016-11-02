require 'net/http'
require 'lightstep/transport/base'

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
      LIGHTSTEP_HOST = "collector.lightstep.com"
      LIGHTSTEP_PORT = 443

      ENCRYPTION_TLS = 'tls'
      ENCRYPTION_NONE = 'none'

      # Initialize the transport
      # @param host [String] host of the domain to the endpoind to push data
      # @param port [Numeric] port on which to connect
      # @param verbose [Numeric] verbosity level. Right now 0-3 are supported
      # @param encryption [ENCRYPTION_TLS, ENCRYPTION_NONE] kind of encryption to use
      # @param access_token [String] access token for LightStep server
      # @return [HTTPJSON]
      def initialize(host: LIGHTSTEP_HOST, port: LIGHTSTEP_PORT, verbose: 0, encryption: ENCRYPTION_TLS, access_token:)
        @host = host
        @port = port
        @verbose = verbose
        @encryption = encryption

        raise ConfigurationError, "access_token must be a string" unless String === access_token
        raise ConfigurationError, "access_token cannot be blank"  if access_token.empty?
        @access_token = access_token
      end

      # Queue a report for sending
      def report(report)
        p report if @verbose >= 3

        https = Net::HTTP.new(@host, @port)
        https.use_ssl = @encryption == ENCRYPTION_TLS
        req = Net::HTTP::Post.new('/api/v0/reports')
        req['LightStep-Access-Token'] = @access_token
        req['Content-Type'] = 'application/json'
        req['Connection'] = 'keep-alive'
        req.body = report.to_json
        res = https.request(req)

        puts res.to_s if @verbose >= 3

        nil
      end
    end
  end
end
