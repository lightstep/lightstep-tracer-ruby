class Util
  def now_micros
    (Time.now.to_f * 1e6).floor.to_i
  end
end
