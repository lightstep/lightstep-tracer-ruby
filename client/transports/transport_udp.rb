require 'json'
require 'socket'
require 'zlib'

class TransportUDP

    MAX_MESSAGE_BYTES = 65535

    attr_reader :sock, :host, :post

    def ensureConnection(options)
        # sock = socket_create(AF_INET, SOCK_DGRAM, SOL_UDP)
        # sock = Socket.new(:INET, :DGRAM)
        sock = UDPSocket.new(Socket::AF_INET)
        unless (sock)
            return
        end

        @sock = sock
        @host = options[:collector_host]
        @port = options[:collector_port]
    end

    def flushReport(auth, report)
        unless (@sock)
            return
        end
        if (auth.nil? || report.nil?)
            return
        end

        # The UDP payload is encoded in a function call like container that
        # maps to the Thrift named arguments.
        #
        # Note: a trade-off is being made here to reduce code path divergence
        # from the "standard" RPC mechanism at the expense of some overhead in
        # creating intermediate Thrift data structures and JSON encoding.
        data = {:auth => auth, :report => report}

        # Prefix with a header for versioning and routing purposes to future
        # proof for other RPC calls.
        # The format is  /<version>/<service>/<function_name>?<json_payload>
        msg = "/v1/crouton/report?" + data.to_json
        if (msg.class.name != 'String')
            puts 'Could not encode report'
            exit(1)
        end
        # msg = gzencode(msg)
        msg = Zlib::deflate(msg)
        len = msg.length

        # Drop messages that are going to fail due to UDP size constraints
        if (len > MAX_MESSAGE_BYTES)
            return
        end
        # bytesSent = @socket_sendto($this->_sock, $msg, strlen($msg), 0, $this->_host, $this->_port);
        bytesSent = sock.send(msg, 0, @host, @port)

        # Reset the connection if something went amiss
        if (bytesSent)
            # socket_close($this->_sock)
            @sock.close
            # $this->_sock = null
            @sock = nil
        end

        # By design, the UDP transport never returns a valid Thrift response
        # object
        return nil
    end
end
