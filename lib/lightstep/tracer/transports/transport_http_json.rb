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
    # Note: this is a rather minimal approach to getting reporting tasks off the
    # calling thread. If the network thread falls behind by > the queue size,
    # it will start slowing down the calling thread.
    @queue = SizedQueue.new(16)
    @thread = _start_network_thread
  end

  def ensure_connection(options)
    @verbose = options[:verbose]
    @host = options[:collector_host]
    @port = options[:collector_port]
    @secure = (options[:collector_encryption] != 'none')
  end

  def flush_report(auth, report)
    if auth.nil? || report.nil?
      puts 'Auth or report not set.' if @verbose > 0
      return nil
    end
    puts report.inspect if @verbose >= 3

    content = _thrift_struct_to_object(report)
    # content = Zlib::deflate(content)

    @queue << {
      host: @host,
      port: @port,
      secure: @secure,
      access_token: auth.access_token,
      content: content,
      verbose: @verbose
    }
    nil
  end

  def close
    # Since close can be called at shutdown and there are multiple Ruby
    # interpreters out there, don't assume the shutdown process will leave the
    # thread alive or have definitely killed it
    if @thread.alive?
      @queue << { signal_exit: true }
      @thread.join
    elsif !@queue.empty?
      begin
        _post_report(@queue.pop(true))
      rescue
        # Ignore the error. Make sure this final flush does not percollate an
        # exception back into the calling code.
      end
    end
  end

  def _start_network_thread
    Thread.new do
      done = false
      until done
        params = @queue.pop
        if params[:signal_exit]
          done = true
        else
          _post_report(params)
        end
      end
    end
  end

  def _post_report(params)
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
