filename = 'lib/lightstep/tracer/thrift/crouton_types.rb'
text = File.read(filename)
text = text.sub(/^require 'thrift'$/, "require_relative './thrift/lib/thrift'")
File.open(filename, 'w') { |file| file.puts text }
puts 'Thrift file patched'
