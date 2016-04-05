require_relative './util'
require_relative '../thrift/types'

class NoOpSpan
    def guid; ''; end
    def setOperationName(name) end
    def addTraceJoinId(key, value) end
    def setEndUserId(id) end
    def tracer ; nil; end
    def setTag(key, value) end
    def setBaggageItem(key, value) end
    def getBaggageItem(key) end
    def logEvent(event, payload = nil) end
    def log(fields) end
    def setParent(span) end
    def finish() end
    def infof(fmt) end
    def warnf(fmt) end
    def errorf(fmt) end
    def fatalf(fmt) end
end
