require 'lightstep/proto/collector_pb'

module LightStep
  class Auth

    def initialize(access_token)
      @access_token = access_token
    end

    def access_token
      @access_token
    end

    def to_proto
      Lightstep::Collector::Auth.new(@access_token)
    end
  end
end