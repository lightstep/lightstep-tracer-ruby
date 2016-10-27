# Empty transport, primarily for unit testing purposes
# FIXME(ngauthier@gmail.com) namespace
class TransportNil
  def initialize
  end

  def flush_report(_auth, _report)
    nil
  end

  def close(immediate)
  end
end
