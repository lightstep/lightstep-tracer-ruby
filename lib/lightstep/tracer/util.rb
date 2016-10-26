# FIXME(ngauthier@gmail.com) namespace
# FIXME(ngauthier@gmail.com) only used in tracer, move into tracer
class Util
  def initialize
    @rng = Random.new
  end

  # Returns a random guid. Note: this intentionally does not use SecureRandom,
  # which is slower and cryptographically secure randomness is not required here.
  def generate_guid
    @rng.bytes(8).unpack('H*')[0]
  end

  def now_micros
    (Time.now.to_f * 1e6).floor.to_i
  end
end
