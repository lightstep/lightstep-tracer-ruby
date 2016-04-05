require_relative '../ruafozy/mersenne_twister'

class Util
  attr_reader :rng

  def initiazlize
    seed = (Time.now.nsec * 1000 * 1000 * 1000).floor
    @rng = Twister.new(seed)
  end

  # ==========================================================
   # Returns an integer in the following closed range (i.e. inclusive,
   # $lower <= $x <= $upper).
  # ==========================================================
  def randIntRange(lower, upper)
    return @rng.rangeint(lower, upper)
  end

  # Returns a positive or *negative* 32-bit integer.
  # http://kingfisher.nfshost.com/sw/twister/
  def randInt32
    return @rng.random
  end

  def nowMicros
    # Note: microtime returns the current time *in seconds* but with
    # microsecond accuracy (not the current time in microseconds!).
    return (Time.now.nsec * 1000 * 1000 * 1000).floor
  end
end
