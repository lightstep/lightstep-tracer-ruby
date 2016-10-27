# FIXME(ngauthier@gmail.com) namespace
class TransportCallback
  def initialize(callback:)
    @callback = callback
  end

  def flush_report(_auth, report)
    @callback.call(report)
    nil
  end

  def close(immediate)
  end
end
