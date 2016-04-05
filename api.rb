# ============================================================
 # @internal
 #
 #  The trace join ID key used for identifying the end user.
# ============================================================

LIGHTSTEP_JOIN_KEY_END_USER_ID = "end_user_id"
# ============================================================
 # Interface for the instrumentation library.
 #
 # This interface is most commonly accessed via LightStep::getInstance()
 # singleton.
# ============================================================
class Tracer

    # ============================================================
    # OpenTracing API
    # ============================================================

    # ============================================================
     # Creates a span object to record the start and finish of an application
     # operation.  The span object can then be used to record further data
     # about this operation, such as which user it is being done on behalf
     # of and log records with arbitrary payload data.
     #
     # @param string $operationName the logical name to use for the operation
     #                              this span is tracking
     # @param array $fields optional array of key-value pairs. Valid pairs are:
     #        'parent' Span the span to use as this span's parent
     #        'tags' array string-string pairs to set as tags on this span
     #        'startTime' float Unix time (in milliseconds) representing the
     #        					start time of this span. Useful for retroactively
     #        					created spans.
     # @return Span
    # ============================================================
    def startSpan(operation_name, fields)
    end

    # TODO: Not yet supported
    # public function inject($span, $format, $carrier);

    # TODO: Not yet supported
    # public function join($span, $format, $carrier);

    # ============================================================
    # LightStep Extentsions
    # ============================================================

    # ============================================================
     # Manually causes any buffered log and span records to be flushed to the
     # server. In most cases, explicit calls to flush() are not required as the
     # logs and spans are sent incrementally over time and at process exit.
    # ============================================================
    def flush
    end

    # ============================================================
     # Returns the generated unique identifier for the runtime.
     #
     # Note: the value is only valid *after* the runtime has been initialized.
     # If called before initialization, this method will return zero.
     #
     # @return int runtime GUID or zero if called before initialization
    # ============================================================
    def guid
    end

    # ============================================================
     # Disables all functionality of the runtime.  All methods are effectively
     # no-ops when in disabled mode.
    # ============================================================
    def disable
    end
end

# ============================================================
 # Interface for the handle to an active span.
# ============================================================
class Span

    # ============================================================
    # OpenTracing API
    # ============================================================

    # ============================================================
    # Sets the name of the operation that the span represents.
    #
    # @param string $name name of the operation
    # ============================================================
    def setOperationName(name)
    end

    # ============================================================
    # Finishes the active span. This should always be called at the
    # end of the logical operation that the span represents.
    # ============================================================
    def finish
    end

    # ============================================================
    # Returns the instance of the Tracer that created the Span.
    #
    # @return Tracer the instance of the Tracer that created this Span.
    # ============================================================
    def tracer
    end

    # ============================================================
    # Sets a tag on the span.  Tags belong to a span instance itself and are
    # not transferred to child or across process boundaries.
    #
    # @param string key the key of the tag
    # @param string value the value of the tag
    # ============================================================
    def setTag(key, value)
    end

    # ============================================================
    # Sets a baggage item on the span.  Baggage is transferred to children and
    # across process boundaries; use sparingly.
    #
    # @param string key the key of the baggage item
    # @param string value the value of the baggage item
    # ============================================================
    def setBaggageItem(key, value)
    end

    # ============================================================
    # Gets a baggage item on the span.
    #
    # @param string key the key of the baggage item
    # @param string value the value of the baggage item
    # ============================================================
    def getBaggageItem(key)
    end

    # ============================================================
    # Logs a stably named event along with an optional payload and associates
    # it with the span.
    #
    # @param string event the name used to identify the event
    # @param mixed payload any data to be associated with the event
    # ============================================================
    def logEvent(event, payload = nil)
    end

    # ============================================================
    # Logs a stably named event along with an optional payload and associates
    # it with the span.
    #
    # @param array fields a set of key-value pairs for specifying an event.
    #        'event' string, required the stable name of the event
    #        'payload' mixed, optional any data to associate with the event
    #        'timestamp' float, optional Unix time (in milliseconds)
    #        		representing the event time.
    # ============================================================
    def log(fields)
    end

    # ============================================================
    # LightStep Extentsions
    # ============================================================

    # ============================================================
    # Sets a string uniquely identifying the user on behalf the
    # span operation is being run. This may be an identifier such
    # as unique username or any other application-specific identifier
    # (as long as it is used consistently for this user).
    #
    # @param string $id a unique identifier of the
    # ============================================================
    def setEndUserId(id)
    end

    # ============================================================
    # Explicitly associates this span as a child operation of the
    # given parent operation. This provides the instrumentation with
    # additional information to construct the trace.
    #
    # @param Span $span the parent span of this span
    # ============================================================
    def setParent(span)
    end

    # ============================================================
    # Sets a trace join ID key-value pair.
    #
    # @param string $key the trace key
    # @param string $value the value to associate with the given key.
    # ============================================================
    def addTraceJoinId(key, value)
    end

    # ============================================================
    # Creates a printf-style log statement that will be associated with
    # this particular operation instance.
    #
    # @param string $fmt a format string as accepted by sprintf
    # ============================================================
    def infof(fmt)
    end

    # ============================================================
    # Creates a printf-style warning log statement that will be associated with
    # this particular operation instance.
    #
    # @param string $fmt a format string as accepted by sprintf
    # ============================================================
    def warnf(fmt)
    end

    # ============================================================
    # Creates a printf-style error log statement that will be associated with
    # this particular operation instance.
    #
    # If the runtime is enabled, the implementation *will* call die() after
    # creating the log (if the runtime is disabled, the log record will
    # not be created and the die() call will not be made).
    #
    # @param string $fmt a format string as accepted by sprintf
    # ============================================================
    def errorf(fmt)
    end

    # ============================================================
    # Creates a printf-style fatal log statement that will be associated with
    # this particular operation instance.
    #
    # @param string $fmt a format string as accepted by sprintf
    # ============================================================
    def fatalf(fmt)
    end

    # ============================================================
    # Returns the unique identifier for the span instance.
    #
    # @return string
    # ============================================================
    def guid
    end
end
