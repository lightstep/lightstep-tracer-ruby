module LightStep
  # Instrument an operation. This is may be called by any LightStep component to
  # record an instrumentation event. This is a compatible API to
  # ActiveSupport::Notifications.
  #
  # event   - Name of the event as a symbol. The event is published under the
  #           lightstep namespace automatically.
  # payload - Hash payload for the event. Available keys are based on the event
  #           being published.
  #
  # Returns the result of executing the block.
  def self.instrument(event, payload = {}, &block)
    if @instrumenter
      block ||= proc {}
      @instrumenter.instrument("#{event}.lightstep", payload, &block)
    elsif block
      block.call(payload)
    end
  end

  # The object that receives instrument messages. This is AS::Notifications by
  # default but may be set to any object that responds to #instrument.
  #
  # Returns an object that responds to #instrument or nil if no instrumentation
  # backend is configured.
  def self.instrumenter
    @instrumenter
  end

  # Configure the instrumentation backend that will receive events. The object
  # must respond to #instrument.
  def self.instrumenter=(object)
    @instrumenter = object
  end

  # If AS::Notifications is available, use it as the instrumentation backend by
  # default. Set LightStep.instrumenter = nil explicitly to disable this.
  if defined?(ActiveSupport::Notifications)
    @instrumenter = ActiveSupport::Notifications
  end
end
