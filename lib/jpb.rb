
require 'pp'
require 'java'


def jruby_spawn

  builder = java.lang.ProcessBuilder.new('ps', 'aux')
#pp builder.environment
  process = builder.start
end

jruby_spawn()

### the target:

def mri_spawn(conf, data)

  t0 = Time.now

  cmd = conf['cmd']

  to = Fugit.parse(conf['timeout'] || '14s')
  to = to.is_a?(Fugit::Duration) ? to.to_sec : 14
  to = 0 if to < 0 # no timeout

  i, o = IO.pipe # _ / stdout
  f, e = IO.pipe # _ / stderr
  r, w = IO.pipe # stdin / _

  pid = Kernel.spawn(cmd, in: r, out: o, err: e)
  w.write(data)
  w.close
  o.close
  e.close

  _, status = Timeout.timeout(to) { Process.wait2(pid) }

  fail SpawnError.new(status, i.read, f.read) if status.exitstatus != 0

  [ i.read, status ]

rescue => err

  class << err; attr_accessor :flor_details; end

  ha = Flor.yes?(conf['on_error_hide_all'])
  cd = (ha || Flor.yes?(conf['on_error_hide_cmd'])) ? '(hidden)' : cmd
  cf = (ha || Flor.yes?(conf['on_error_hide_conf'])) ? '(hidden)' : conf

  err.flor_details = {
    cmd: cd, conf: cf,
    timeout: to,
    pid: pid,
    start: Flor.tstamp(t0),
    duration: Fugit.parse(Time.now - t0).to_plain_s }

  (Process.kill(9, pid) rescue nil) \
    unless Flor.no?(conf['on_error_kill'])

  raise

ensure

  [ i, o, f, e, r, w ].each { |x| x.close rescue nil }
end

