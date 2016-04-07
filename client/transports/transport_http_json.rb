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

    def ensureConnection(options)
        @verbose = options[:verbose]
        @host = options[:collector_host]
        @port = options[:collector_port]
        @secure = true

        # The prefixed protocol is only needed for secure connections
        if options[:collector_encryption] == 'none'
            @secure = false
        end
    end

    def flushReport(auth, report)
        if (auth.nil? || report.nil?)
            if (@verbose > 0)
                puts 'Auth or report not set.'
                exit(1)
            end
            return nil
        end

        if (@verbose >= 3)
            puts report.inspect
        end

        content = self._thrift_struct_to_object(report)
        # content = Zlib::deflate(content)

        https = Net::HTTP.new(@host, @port)
        https.use_ssl = @secure
        req = Net::HTTP::Post.new('/api/v0/reports')
        req['LightStep-Access-Token'] = auth.access_token
        req['Content-Type'] = 'application/json'
        req['Connection'] = 'keep-alive'
        req.body = content.to_json
        res = https.request(req)
        return nil
    end

    def _thrift_array_to_object(value)
        arr = Array.new
        value.each do |elem|
            arr << self._thrift_struct_to_object(elem)
        end
        arr
    end

    def _thrift_struct_to_object(report)
        obj = Hash.new
        report.each_field do |fid, field_info|
            type = field_info[:type]
            name = field_info[:name]
            value = report.instance_variable_get("@#{name}")

            if value == nil
                # Skip
            elsif type == Thrift::Types::LIST
                obj[name] = self._thrift_array_to_object(value)
            elsif type == Thrift::Types::STRUCT
                obj[name] = self._thrift_struct_to_object(value)
            else
                obj[name] = value
            end
        end
        obj
    end
end
