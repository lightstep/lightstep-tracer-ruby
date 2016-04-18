require 'json'
require 'zlib'
require 'net/http'
require 'thrift'

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

  # In many other languages the built-in "toJSON" methods and functions
  # generally do what is desired. In Ruby, the Thrift types need to be
  # converted to plain arrays and hashes before calling to_json.
  def _thrift_array_to_object(value)
    arr = []
    value.each do |elem|
      arr << _thrift_struct_to_object(elem)
    end
    arr
  end

  def _thrift_struct_to_object(report)
    obj = {}
    report.each_field do |_fid, field_info|
      type = field_info[:type]
      name = field_info[:name]
      value = report.instance_variable_get("@#{name}")

      if value.nil?
      # Skip
      elsif type == Thrift::Types::LIST
        obj[name] = _thrift_array_to_object(value)
      elsif type == Thrift::Types::STRUCT
        obj[name] = _thrift_struct_to_object(value)
      else
        obj[name] = value
      end
    end
    obj
  end
end
