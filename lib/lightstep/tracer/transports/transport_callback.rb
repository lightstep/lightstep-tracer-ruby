# FIXME(ngauthier@gmail.com) unused
require_relative './util'

# FIXME(ngauthier@gmail.com) namespace
class TransportCallback
  def initialize
    @callback = nil
  end

  def ensure_connection(options)
    @callback = options[:transport_callback]
  end

  def flush_report(_auth, report)
    @callback.call(report)
    nil
  end

  def close(immediate)
  end
end
