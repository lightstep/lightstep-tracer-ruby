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
      QUEUE_SIZE = 16

      ENCRYPTION_TLS = 'tls'
      ENCRYPTION_NONE = 'none'

      class QueueFullError < LightStep::Error; end

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

        start_queue
      end

      # Queue a report for sending
      def report(report)
        p report if @verbose >= 3
        # TODO(ngauthier@gmail.com): the queue could be full here if we're
        # lagging, which would cause this to block!
        @queue.push({
          host: @host,
          port: @port,
          encryption: @encryption,
          access_token: @access_token,
          content: report,
          verbose: @verbose
        }, true)
        nil
      rescue ThreadError
        raise QueueFullError
      end

      # Flush the current queue
      def flush
        close
        start_queue
      end

      # Clear the current queue, deleting pending items
      def clear
        @queue.clear
      end

      # Close the transport. No further data can be sent!
      def close
        @queue.close
        @thread.join
      end

      private

      def start_queue
        @queue = SizedQueue.new(QUEUE_SIZE)
        @thread = start_thread(@queue)
      end

      # TODO(ngauthier@gmail.com) abort on exception?
      def start_thread(queue)
        Thread.new do
          while item = queue.pop
            post_report(item)
          end
        end
      end

      def post_report(params)
        https = Net::HTTP.new(params[:host], params[:port])
        https.use_ssl = params[:encryption] == ENCRYPTION_TLS
        req = Net::HTTP::Post.new('/api/v0/reports')
        req['LightStep-Access-Token'] = params[:access_token]
        req['Content-Type'] = 'application/json'
        req['Connection'] = 'keep-alive'
        req.body = params[:content].to_json
        res = https.request(req)

        puts res.to_s if params[:verbose] >= 3

        # TODO(ngauthier@gmail.com): log unknown commands
        # TODO(ngauthier@gmail.com): log errors from server
      end
    end
  end
end
