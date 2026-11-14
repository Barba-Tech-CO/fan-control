// fanctld — root helper. Applies a fan mode and listens on a unix socket.
// Commands (one line per connection): mode | auto | hold <lo> <hi> | fixed <rpm>
// State-changing commands are accepted only from root or the console user (getpeereid).
import Foundation

let socketPath = ProcessInfo.processInfo.environment["FANCTL_SOCK"] ?? "/var/run/fanctl.sock"
let hardLimitC = 95.0  // always full fan at or above this, whatever the mode

enum Mode { case auto, hold(Double, Double), fixed(Float) }

nonisolated(unsafe) var stopRequested = false
nonisolated(unsafe) var mode = Mode.auto
nonisolated(unsafe) var holdRpm: Float? = nil  // nil = macOS auto while holding

guard let smc = try? SMC() else { fputs("cannot open AppleSMC\n", stderr); exit(1) }
let fan = Fan(smc)
let sensor = TempSensor()

func describe() -> String {
  switch mode {
  case .auto: return "auto"
  case .hold(let lo, let hi): return "hold \(lo) \(hi)"
  case .fixed(let r): return "fixed \(Int(r))"
  }
}

func control() {
  guard let t = sensor.maxC() else { holdRpm = nil; fan.setAuto(); return }
  if t >= hardLimitC { try? fan.setManual(fan.max); return }
  switch mode {
  case .auto:
    fan.setAuto()
  case .fixed(let r):
    do { try fan.setManual(r) } catch { fan.setAuto() }
  case .hold(let lo, let hi):
    if t > hi {
      let current = holdRpm ?? max(fan.actual, fan.min)
      holdRpm = min(current + 100 + Float(t - hi) * 150, fan.max)
    } else if t < lo, let r = holdRpm {
      holdRpm = r - 100 > fan.min ? r - 100 : nil
    }
    if let r = holdRpm { do { try fan.setManual(r) } catch { fan.setAuto(); holdRpm = nil } } else { fan.setAuto() }
  }
}

/// Owner of /dev/console = the user logged in at the Mac (root when nobody is).
func consoleUID() -> uid_t {
  var st = stat()
  return stat("/dev/console", &st) == 0 ? st.st_uid : 0
}

func handle(_ line: String, authorized: Bool) -> String {
  let p = line.split(separator: " ").map(String.init)
  if p.first != "mode" && !authorized { return "error unauthorized" }
  switch (p.first, p.count) {
  case ("mode", 1): return describe()
  case ("auto", 1): mode = .auto
  case ("hold", 3):
    guard let lo = Double(p[1]), let hi = Double(p[2]), lo >= 50, hi <= 100, lo + 2 <= hi else { return "error range" }
    mode = .hold(lo, hi); holdRpm = nil
  case ("fixed", 2):
    guard let r = Float(p[1]), r.isFinite else { return "error rpm" }
    mode = .fixed(min(max(r, fan.min), fan.max))
  default: return "error command"
  }
  control()
  return describe()
}

func makeServer() -> Int32 {
  unlink(socketPath)
  let fd = socket(AF_UNIX, SOCK_STREAM, 0)
  var addr = sockaddr_un()
  addr.sun_family = sa_family_t(AF_UNIX)
  withUnsafeMutableBytes(of: &addr.sun_path) { socketPath.utf8CString.withUnsafeBytes($0.copyMemory(from:)) }
  let len = socklen_t(MemoryLayout<sockaddr_un>.size)
  let ok = withUnsafePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, len) } }
  guard ok == 0 else { fputs("bind failed\n", stderr); exit(1) }
  chmod(socketPath, 0o666)
  listen(fd, 4)
  return fd
}

signal(SIGINT) { _ in stopRequested = true }
signal(SIGTERM) { _ in stopRequested = true }
let server = makeServer()
var lastControl = Date.distantPast

while !stopRequested {
  var pfd = pollfd(fd: server, events: Int16(POLLIN), revents: 0)
  if poll(&pfd, 1, 1000) > 0, pfd.revents & Int16(POLLIN) != 0 {
    let c = accept(server, nil, nil)
    if c >= 0 {
      // A silent client must not stall the control loop (and the thermal safety with it).
      var tv = timeval(tv_sec: 1, tv_usec: 0)
      setsockopt(c, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
      setsockopt(c, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
      // Only root and the console user may change the fan; anyone may read the mode.
      var uid: uid_t = 0, gid: gid_t = 0
      let authorized = getpeereid(c, &uid, &gid) == 0 && (uid == 0 || uid == consoleUID())
      var buf = [UInt8](repeating: 0, count: 128)
      let n = read(c, &buf, 127)
      let line = n > 0 ? String(decoding: buf[0..<n], as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines) : ""
      let reply = handle(line, authorized: authorized) + "\n"
      _ = reply.withCString { write(c, $0, strlen($0)) }
      close(c)
    }
  }
  if Date().timeIntervalSince(lastControl) >= 2 { control(); lastControl = Date() }
}
fan.setAuto()
unlink(socketPath)
