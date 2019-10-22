module RackHelpers
  def to_rack_env(input_hash)
    input_hash.inject({}) do |memo, (k, v)|
      memo[to_rack_key(k)] = v
      memo
    end
  end

  def to_rack_key(key)
    "HTTP_#{key.gsub("-", "_").upcase!}"
  end
end
