require 'net/http'

module LightStep
  module Transport
    class HTTPJSON
      def initialize(host:, port:, verbose: 0, secure: true)
        # Configuration
        @host = host
        @port = port
        @verbose = verbose
        @secure = secure

        @thread = nil
        @thread_pid = 0 # process ID that created the thread
        @queue = nil
      end

      def flush_report(auth, report)
        if auth.nil? || report.nil?
          puts 'Auth or report not set.' if @verbose > 0
          return nil
        end
        puts report.inspect if @verbose >= 3

        _check_process_id

        # Lazily re-create the queue and thread. Closing the transport as well as
        # a process fork may have reset it to nil.
        if @thread.nil? || !@thread.alive?
          @thread_pid = Process.pid
          @thread = _start_network_thread
        end
        @queue = SizedQueue.new(16) if @queue.nil?

        @queue << {
          host: @host,
          port: @port,
          secure: @secure,
          access_token: auth['access_token'],
          content: report,
          verbose: @verbose
        }
        nil
      end

      # Process.fork can leave SizedQueue and thread in a untrustworthy state. If the
      # process ID has changed, reset the the thread and queue.
      # FIXME(ngauthier@gmail.com) private
      def _check_process_id
        if Process.pid != @thread_pid
          Thread.kill(@thread) unless @thread.nil?
          @thread = nil
          @queue = nil
        end
      end

      def close(discardPending)
        return if @queue.nil?
        return if @thread.nil?

        _check_process_id

        # Since close can be called at shutdown and there are multiple Ruby
        # interpreters out there, don't assume the shutdown process will leave the
        # thread alive or have definitely killed it
        if !@thread.nil? && @thread.alive?
          @queue << { signal_exit: true } unless @queue.nil?
          @thread.join
        elsif !@queue.empty? && !discardPending
          begin
            _post_report(@queue.pop(true))
          # FIXME(ngauthier@gmail.com) naked rescue
          rescue
            # Ignore the error. Make sure this final flush does not percollate an
            # exception back into the calling code.
          end
        end

        # Clear the member variables so the transport is in a known state and can be
        # restarted safely
        @queue = nil
        @thread = nil
      end

      # FIXME(ngauthier@gmail.com) private
      # TODO(ngauthier@gmail.com) abort on exception?
      # FIXME(ngauthier@gmail.com) plain loop + break
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

      # FIXME(ngauthier@gmail.com) private
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
  end
end
