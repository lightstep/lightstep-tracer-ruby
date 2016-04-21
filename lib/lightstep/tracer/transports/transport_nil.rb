# Empty transport, primarily for unit testing purposes
class TransportNil
  def initialize
  end

  def ensure_connection(options)
  end

  def flush_report(_auth, _report)
    nil
  end

  def close
  end
end
