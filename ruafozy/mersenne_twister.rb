module ExtendedFixnum
  module BitOperations
    def last_bits(num)
      result = 0
      num.times{|x| result += self[x] << x}
      result
    end
  end
end

class Fixnum
  include ExtendedFixnum::BitOperations
end

class Bignum
  include ExtendedFixnum::BitOperations
end

class MersenneTwister

  def initialize(seed_num = nil)
    seed_num ||= rand(40227307522636928640) + 1 
    @mt = [] #(0..623).map{0}
    @index = 0
    seed(seed_num)
  end

  def randomize
    generate_numbers
  end

  def random
    extract_number
  end

  private

    def extract_number
      generate_numbers if @index == 0

      y = @mt[@index]
      y = y ^ (y >> 11)
      y = y ^ ((y << 7) & 2636928640)
      y = y ^ ((y << 15) & 4022730752)
      y = y ^ (y >> 18)

      @index = (@index + 1) % 624
      y
    end

    def seed(seed_num)
      @mt[0] = seed_num
      for i in 1..623
        @mt[i] = (1812433253 * (@mt[i-1] ^ (@mt[i-1] >> 30)) + i).last_bits(32)
      end
      true
    end

    def generate_numbers
      for i in 0..623
        y = @mt[i][31] + @mt[(i+1) % 624].last_bits(31)
        @mt[i] = @mt[(i + 397) % 624] ^ (y >> 1)
        @mt[i] = @mt[i] ^ 2567483615 if y.odd?
      end
      true
    end
end
