require 'thrift'

# In many other languages the built-in "toJSON" methods and functions
# generally do what is desired. In Ruby, the Thrift types need to be
# converted to plain arrays and hashes before calling to_json.
def _thrift_array_to_object(value)
  arr = []
  value.each do |elem|
    arr << _thrift_struct_to_object(elem)
  end
  arr
end

def _thrift_struct_to_object(report)
  obj = {}
  report.each_field do |_fid, field_info|
    type = field_info[:type]
    name = field_info[:name]
    value = report.instance_variable_get("@#{name}")

    if value.nil?
    # Skip
    elsif type == Thrift::Types::LIST
      obj[name] = _thrift_array_to_object(value)
    elsif type == Thrift::Types::STRUCT
      obj[name] = _thrift_struct_to_object(value)
    else
      obj[name] = value
    end
  end
  obj
end
