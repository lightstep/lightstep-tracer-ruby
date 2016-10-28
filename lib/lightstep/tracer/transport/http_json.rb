require 'net/http'
require 'lightstep/tracer/transport/base'

module LightStep
  module Transport
    # HTTPJSON is a transport that sends reports via HTTP in JSON format.
    # It is thread-safe, however it is *not* fork-safe. When forking, all items
    # in the queue will be copied and sent in duplicate. Therefore, when forking,
    # you should first flush the queue with `flush`, then fork, then resume
    # use of the Tracer.
    #
    # You may also simply initialize the tracer after forking, if you are forking
    # at the beginning of your server to establish worker processes.
    class HTTPJSON < Base
      LIGHTSTEP_HOST = "collector.lightstep.com"
      LIGHTSTEP_PORT = 443
      QUEUE_SIZE = 16

      def initialize(host: LIGHTSTEP_HOST, port: LIGHTSTEP_PORT, verbose: 0, secure: true, access_token:)
        @host = host
        @port = port
        @verbose = verbose
        @secure = secure

        raise ConfigurationError, "access_token must be a string" unless String === access_token
        raise ConfigurationError, "access_token cannot be blank"  if access_token.empty?
        @access_token = access_token

        start_queue
      end

      def report(report)
        p report if @verbose >= 3
        # TODO(ngauthier@gmail.com): the queue could be full here if we're
        # lagging, which would cause this to block!
        @queue << {
          host: @host,
          port: @port,
          secure: @secure,
          access_token: @access_token,
          content: report,
          verbose: @verbose
        }
        nil
      end

      def flush
        close
        start_queue
      end

      def clear
        @queue.clear
      end

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
        https.use_ssl = params[:secure]
        req = Net::HTTP::Post.new('/api/v0/reports')
        req['LightStep-Access-Token'] = params[:access_token]
        req['Content-Type'] = 'application/json'
        req['Connection'] = 'keep-alive'
        req.body = params[:content].to_json
        res = https.request(req)

        puts res.to_s if params[:verbose] >= 3
      end
    end
  end
end
