require 'json'
require 'lightstep'
require 'opentracing'
require 'net/http'
require 'pp'
require 'uri'

$base_url = "http://localhost:8000"

$test_tracer = LightStep::Tracer.new(
  component_name: 'lightstep/ruby/example',
  transport: LightStep::Transport::HTTPJSON.new(
    host: 'localhost',
    port: 8000,
    encryption: LightStep::Transport::HTTPJSON::ENCRYPTION_NONE,
    access_token: 'none'
  )
)
$noop_tracer = OpenTracing::Tracer.new

$prime_work = 982451653
$logs_memory = ""
$logs_size_max = (1 << 20)
$nanos_per_second = 1e9

def prepare_logs()
  (0..$logs_size_max-1).each do |x|
    $logs_memory << ("A".ord + x%26).chr
  end
end

prepare_logs()

def do_work(n)
  x = $prime_work
  while n != 0 do
    x *= $prime_work
    x %= 4294967296
    n -= 1
  end
  return x
end

def test_body(tracer, control)
  repeat    = control['Repeat']
  sleepnano = control['Sleep']
  sleepival = control['SleepInterval']
  work      = control['Work']
  logn      = control['NumLogs']
  logsz     = control['BytesPerLog']
  sleep_debt = 0  # Accumulated nanoseconds
  sleeps    = 0
  answer    = 0

  (1..repeat).each do
    span = tracer.start_span('span/test')
    (1..logn).each do
      span.log_event("testlog", $logs_memory[0..logsz])
    end
    answer += do_work(work)
    span.finish()
    sleep_debt += sleepnano
    if sleep_debt <= sleepival
      next
    end
    before = Time.now.to_f
    sleep(sleep_debt / $nanos_per_second)
    elapsed_secs = Time.now.to_f - before
    elapsed = (elapsed_secs * $nanos_per_second).round
    sleeps += elapsed_secs
    sleep_debt -= elapsed
  end
  return sleeps, answer
end

def loop()
  while true do
    uri = URI.parse($base_url + '/control')
    resp = Net::HTTP.get(uri)
    control = JSON.parse(resp)

    concurrent = control['Concurrent']
    trace = control['Trace']

    if control['Exit']
      exit(0)
    end

    tracer = nil
    if trace
      tracer = $test_tracer
    else
      tracer = $noop_tracer
    end

    before = Time.now.to_f

    # Note: Concurrency test not implemented
    sleeps, answer = test_body(tracer, control)

    after = Time.now.to_f
    flush_dur = 0.0

    if trace
      tracer.flush()
      flush_dur = Time.now.to_f - after
    end

    elapsed = after - before

    path = sprintf('/result?timing=%f&flush=%f&s=%f&a=%s', elapsed, flush_dur, sleeps, answer)

    uri = URI.parse($base_url + path)
    resp = Net::HTTP.get(uri)
  end
end

def backtrace_for_all_threads(signame)
  File.open("/tmp/ruby_backtrace_#{Process.pid}.txt","a") do |f|
      f.puts "--- got signal #{signame}, dump backtrace for all threads at #{Time.now}"
      if Thread.current.respond_to?(:backtrace)
        Thread.list.each do |t|
          f.puts t.inspect
          PP.pp(t.backtrace.delete_if {|frame| frame =~ /^#{File.expand_path(__FILE__)}/},
               f) # remove frames resulting from calling this method
        end
      else
          PP.pp(caller.delete_if {|frame| frame =~ /^#{File.expand_path(__FILE__)}/},
               f) # remove frames resulting from calling this method
      end
  end
end

Signal.trap(29) do
  backtrace_for_all_threads("INFO")
end

loop()
