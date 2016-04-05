require 'json'
require 'zlib'
require 'socket'

class TransportHTTPJSON

    def initialize
        @host = ''
        @port = 0
        @verbose = 0
    end

    def ensureConnection(options)
        @verbose = options[:verbose]

        @host = options[:collector_host]
        @port = options[:collector_port]

        # The prefixed protocol is only needed for secure connections
        if (options[:collector_secure])
            @host = 'ssl://' + @host
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

        content += report.to_json
        # content = gzencode(content)
        content = Zlib::deflate(content)

        header = "Host: " + @host + "\r\n"
        header += "User-Agent: LightStep-Ruby\r\n"
        header += "LightStep-Access-Token: " + auth.access_token + "\r\n"
        header += "Content-Type: application/json\r\n"
        header += "Content-Length: " + content.length + "\r\n"
        header += "Content-Encoding: gzip\r\n"
        header += "Connection: keep-alive\r\n\r\n"

        # TODO: This is PHP code, not Ruby code!!!!
        #
        # fp = @pfsockopen(@host, @port, errno, errstr);
        # unless (fp)
        #     if (@verbose > 0)
        #         # error_log(errstr)
        #         puts errstr.to_s
        #         exit(1)
        #     end
        #     return nil
        # end
        # @fwrite(fp, "POST /api/v0/reports HTTP/1.1\r\n")
        # @fwrite(fp, header + content)
        # @fflush(fp)
        # @fclose(fp)

        return nil
    end
end
