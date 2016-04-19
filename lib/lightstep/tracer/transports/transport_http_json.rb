require 'json'
require 'zlib'
require 'net/http'
require_relative './util'

class TransportHTTPJSON
  def initialize
    @host = ''
    @port = 0
    @verbose = 0
    @secure = true
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

    https = Net::HTTP.new(@host, @port)
    https.use_ssl = @secure
    req = Net::HTTP::Post.new('/api/v0/reports')
    req['LightStep-Access-Token'] = auth.access_token
    req['Content-Type'] = 'application/json'
    req['Connection'] = 'keep-alive'
    req.body = content.to_json
    res = https.request(req)
    nil
  end
end
