require 'spec_helper'
require 'thread'
require 'rack'
require 'rack/server'

class App
  attr_reader :mutex, :calls

  def initialize
    @mutex = Mutex.new
    @calls = 0
  end

  def call(env)
    # Note we are not unlocking...
    @calls += 1

    @mutex.lock
    [200, {}, ["application"]]
  end
end


describe LightStep::Transport::HTTPJSON do
  it 'requires an access token' do
    expect { LightStep::Transport::HTTPJSON.new }.to raise_error(ArgumentError)
  end

  it 'is thread safe' do
    app = App.new
    router_thread = Thread.new do
      Thread.abort_on_exception = true
      Rack::Server.start(app: app, Port: 9001)
    end

    # Let the server startup
    sleep 0.250

    t = LightStep::Transport::HTTPJSON.new host: "127.0.0.1", port: "9001", encryption: false, access_token: "foo"

    app.mutex.lock

    report_a = Thread.new do
      t.report hello: true
    end

    report_b = Thread.new do
      t.report hello: true
    end

    sleep 0.250

    # Only one thread will have been able to call
    expect(app.calls).to eq(1)

    router_thread.terminate
    report_a.terminate
    report_b.terminate
  end
end
