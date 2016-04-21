
require_relative './util'

class TransportCallback
  def initialize
    @callback = nil
  end

  def ensure_connection(options)
    @callback = options[:transport_callback]
  end

  def flush_report(_auth, report)
    content = _thrift_struct_to_object(report)
    @callback.call(content)
    nil
  end

  def close
  end
end
