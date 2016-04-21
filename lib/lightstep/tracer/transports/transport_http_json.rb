require 'json'
require 'zlib'
require 'net/http'
require 'thread'
require_relative './util'

class TransportHTTPJSON
  def initialize
    # Configuration
    @host = ''
    @port = 0
    @verbose = 0
    @secure = true

    # Network requests occur off the calling thread
    @queue = SizedQueue.new(1)
    @thread = _start_reporting_thread
  end

  def ensure_connection(options)
    @verbose = options[:verbose]
    @host = options[:collector_host]
    @port = options[:collector_port]
    @secure = true

    # The prefixed protocol is only needed for secure connections
    @secure = false if options[:collector_encryption] == 'none'
  end

  def flush_report(auth, report)
    if auth.nil? || report.nil?
      puts 'Auth or report not set.' if @verbose > 0
      return nil
    end
    puts report.inspect if @verbose >= 3

    content = _thrift_struct_to_object(report)
    # content = Zlib::deflate(content)

    puts 'Pushed to queue...'
    @queue << {
      host: @host,
      port: @port,
      secure: @secure,
      access_token: auth.access_token,
      conent: content
    }
    nil
  end

  def close
    puts "Wait for reporting thread: #{queue.num_waiting}"
    @thread.join
  end

  def _start_reporting_thread
    Thread.new do
      puts 'Starting thread...'
      loop do
        puts 'Waiting for work...'
        params = @queue.pop

        puts "Starting request #{params}"
        https = Net::HTTP.new(params[:host], params[:port])
        https.use_ssl = params[:secure]
        req = Net::HTTP::Post.new('/api/v0/reports')
        req['LightStep-Access-Token'] = params[:access_token]
        req['Content-Type'] = 'application/json'
        req['Connection'] = 'keep-alive'
        req.body = params[:content].to_json
        res = https.request(req)
        puts "Finished request #{res.inspect}"
      end
    end
  end
end
