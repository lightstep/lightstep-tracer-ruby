# FIXME(ngauthier@gmail.com) move into root lib file
module Lightstep
  module Tracer
    FORMAT_TEXT_MAP = 1
    FORMAT_BINARY = 2

    CARRIER_TRACER_STATE_PREFIX = 'ot-tracer-'.freeze
    CARRIER_BAGGAGE_PREFIX = 'ot-baggage-'.freeze
  end
end
