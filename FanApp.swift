import SwiftUI
import Charts
import Foundation

let socketPath = "/var/run/fanctl.sock"
let daemonLabel = "com.local.fanctld"

enum Choice: String, CaseIterable, Identifiable {
  case auto = "Auto", hold = "Hold", fixed = "Manual"
  var id: String { rawValue }
}

/// One-line request/response to the root helper. nil = helper not reachable.
func askHelper(_ line: String) -> String? {
  let fd = socket(AF_UNIX, SOCK_STREAM, 0)
  guard fd >= 0 else { return nil }
  defer { close(fd) }
  var addr = sockaddr_un()
  addr.sun_family = sa_family_t(AF_UNIX)
  withUnsafeMutableBytes(of: &addr.sun_path) { socketPath.utf8CString.withUnsafeBytes($0.copyMemory(from:)) }
  let len = socklen_t(MemoryLayout<sockaddr_un>.size)
  let ok = withUnsafePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, len) } }
  guard ok == 0 else { return nil }
  _ = (line + "\n").withCString { write(fd, $0, strlen($0)) }
  var buf = [UInt8](repeating: 0, count: 128)
  let n = read(fd, &buf, 127)
  return n > 0 ? String(decoding: buf[0..<n], as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines) : nil
}

struct Sample: Identifiable { let id = UUID(); let t: Date; let temp: Double; let rpm: Double }

@MainActor
final class Model: ObservableObject {
  @Published var temp: Double?
  @Published var rpm: Float = 0
  @Published var helperUp = false
  @Published var choice: Choice = .auto
  @Published var lo: Double = 80
  @Published var hi: Double = 85
  @Published var fixedRpm: Float = 3000
  @Published var error: String?
  @Published var history: [Sample] = []

  let fanMin: Float, fanMax: Float
  private let smc = try? SMC()
  private let sensor = TempSensor()
  private var synced = false
  private var timer: Timer?

  init() {
    fanMin = smc?.float("F0Mn") ?? 1000
    fanMax = smc?.float("F0Mx") ?? 4900
    refresh()
    timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
      Task { @MainActor in self?.refresh() }
    }
  }

  var menuTitle: String { temp.map { String(format: "%.0f°", $0) } ?? "--" }
  var tempColor: Color {
    switch temp ?? 0 { case ..<80: Theme.accent; case ..<90: Theme.amber; default: Theme.hot }
  }

  func refresh() {
    temp = sensor.maxC()
    rpm = smc?.float("F0Ac") ?? 0
    if let t = temp {
      history.append(Sample(t: Date(), temp: t, rpm: Double(rpm)))
      if history.count > 180 { history.removeFirst(history.count - 180) }
    }
    Task.detached {
      let reply = askHelper("mode")
      await MainActor.run { self.helperUp = reply != nil; if let r = reply, !self.synced { self.adopt(r) } }
    }
  }

  /// Take over the helper's current mode the first time we reach it.
  private func adopt(_ reply: String) {
    synced = true
    let p = reply.split(separator: " ")
    switch p.first {
    case "hold" where p.count == 3: choice = .hold; lo = Double(p[1]) ?? lo; hi = Double(p[2]) ?? hi
    case "fixed" where p.count == 2: choice = .fixed; fixedRpm = Float(p[1]) ?? fixedRpm
    default: choice = .auto
    }
  }

  func apply() {
    let cmd: String
    switch choice {
    case .auto: cmd = "auto"
    case .hold: cmd = "hold \(lo) \(hi)"
    case .fixed: cmd = "fixed \(Int(fixedRpm))"
    }
    Task.detached {
      let reply = askHelper(cmd)
      await MainActor.run { self.error = reply?.hasPrefix("error") == true ? reply : nil; self.helperUp = reply != nil }
    }
  }

  func installHelper() {
    guard let res = Bundle.main.resourcePath else { return }
    let bin = "/Library/PrivilegedHelperTools/com.local.fanctld", plist = "/Library/LaunchDaemons/\(daemonLabel).plist"
    let sh = "launchctl bootout system/\(daemonLabel) 2>/dev/null; mkdir -p /Library/PrivilegedHelperTools"
      + " && install -o root -g wheel -m 755 '\(res)/fanctld' \(bin)"
      + " && install -o root -g wheel -m 644 '\(res)/\(daemonLabel).plist' \(plist)"
      + " && rm -f /usr/local/libexec/fanctld && launchctl bootstrap system \(plist)"
    var err: NSDictionary?
    NSAppleScript(source: "do shell script \"\(sh)\" with administrator privileges")?.executeAndReturnError(&err)
    error = err?[NSAppleScript.errorMessage] as? String
    synced = false
    refresh()
  }
}


// MARK: Views

enum Theme {
  static let bg = Color(red: 0.055, green: 0.063, blue: 0.078)
  static let card = Color(red: 0.09, green: 0.10, blue: 0.125)
  static let line = Color.white.opacity(0.07)
  static let accent = Color(red: 0.30, green: 0.82, blue: 0.88)
  static let amber = Color(red: 1.0, green: 0.71, blue: 0.33)
  static let hot = Color(red: 1.0, green: 0.37, blue: 0.34)
  static let dim = Color.white.opacity(0.45)
}

struct Panel<Content: View>: View {
  @ViewBuilder var content: Content
  var body: some View {
    content.padding(16).frame(maxWidth: .infinity, alignment: .leading)
      .background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
      .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.line))
  }
}

struct Caption: View {
  let text: String
  init(_ t: String) { text = t }
  var body: some View { Text(text).font(.system(size: 11, weight: .semibold)).tracking(1.4).foregroundStyle(Theme.dim) }
}

final class SpinState: ObservableObject { var phase = 0.0; var last = Date() }

/// Fan glyph whose rotation speed follows the real RPM (scaled down so it stays readable).
struct SpinningFan: View {
  let rpm: Double
  let color: Color
  @StateObject private var spin = SpinState()
  var body: some View {
    TimelineView(.animation) { ctx in
      let dt = ctx.date.timeIntervalSince(spin.last)
      let _ = { spin.phase = (spin.phase + rpm * 0.4 * dt).truncatingRemainder(dividingBy: 360); spin.last = ctx.date }()
      Image(systemName: "fan.fill").font(.system(size: 54)).foregroundStyle(color.gradient).rotationEffect(.degrees(spin.phase))
    }
  }
}

struct StepChip: View {
  let label: String
  @Binding var value: Double
  let range: ClosedRange<Double>
  let onChange: () -> Void
  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Caption(label)
      HStack(spacing: 0) {
        stepButton("minus", -1)
        Text("\(Int(value))°").font(.system(size: 22, weight: .medium, design: .rounded)).monospacedDigit().frame(maxWidth: .infinity)
        stepButton("plus", 1)
      }
      .background(.white.opacity(0.06), in: Capsule())
    }
  }
  private func stepButton(_ icon: String, _ d: Double) -> some View {
    Button { value = min(max(value + d, range.lowerBound), range.upperBound); onChange() } label: {
      Image(systemName: icon).font(.system(size: 13, weight: .bold)).frame(width: 40, height: 36).contentShape(Rectangle())
    }.buttonStyle(.plain)
  }
}

struct ModePicker: View {
  @EnvironmentObject var m: Model
  var body: some View {
    HStack(spacing: 4) {
      ForEach(Choice.allCases) { c in
        Button { m.choice = c; m.apply() } label: {
          Text(c.rawValue).font(.system(size: 13, weight: .semibold)).frame(maxWidth: .infinity).padding(.vertical, 9)
            .background(m.choice == c ? Theme.accent : .clear, in: Capsule())
            .foregroundStyle(m.choice == c ? Color.black.opacity(0.85) : Theme.dim)
        }.buttonStyle(.plain)
      }
    }
    .padding(4).background(.white.opacity(0.06), in: Capsule())
  }
}

struct ControlPanel: View {
  @EnvironmentObject var m: Model
  private var percent: Int { Int(((m.fixedRpm - m.fanMin) / (m.fanMax - m.fanMin) * 100).rounded()) }
  var body: some View {
    Panel {
      VStack(alignment: .leading, spacing: 16) {
        VStack(alignment: .leading, spacing: 16) {
          ModePicker()
          Group {
            switch m.choice {
            case .auto:
              Text("macOS decides the fan speed on its own curve.").font(.callout).foregroundStyle(Theme.dim)
            case .hold:
              HStack(spacing: 14) {
                StepChip(label: "MIN", value: $m.lo, range: 50...97) { if m.hi < m.lo + 2 { m.hi = m.lo + 2 }; m.apply() }
                StepChip(label: "MAX", value: $m.hi, range: 52...100) { if m.lo > m.hi - 2 { m.lo = m.hi - 2 }; m.apply() }
              }
            case .fixed:
              VStack(alignment: .leading, spacing: 6) {
                HStack {
                  Caption("FAN SPEED")
                  Spacer()
                  Text("\(percent)% · \(Int(m.fixedRpm)) rpm").font(.system(size: 15, weight: .medium, design: .rounded)).monospacedDigit()
                }
                Slider(value: Binding(get: { Double(m.fixedRpm) }, set: { m.fixedRpm = Float($0) }),
                       in: Double(m.fanMin)...Double(m.fanMax), step: 100, onEditingChanged: { if !$0 { m.apply() } }).tint(Theme.accent)
                HStack {
                  Text("\(Int(m.fanMin))").font(.caption2).foregroundStyle(Theme.dim)
                  Spacer()
                  Text("\(Int(m.fanMax))").font(.caption2).foregroundStyle(Theme.dim)
                }
              }
            }
          }
          .frame(minHeight: 62, alignment: .topLeading)
        }
        .disabled(!m.helperUp).opacity(m.helperUp ? 1 : 0.4)

        if !m.helperUp {
          Text("Controls unlock after a one-time install of a small background helper. Your admin password is asked once.")
            .font(.callout).foregroundStyle(Theme.dim)
          Button { m.installHelper() } label: {
            Text("Install helper").font(.system(size: 14, weight: .semibold)).frame(maxWidth: .infinity).padding(.vertical, 10)
              .background(Theme.accent, in: Capsule()).foregroundStyle(Color.black.opacity(0.85))
          }.buttonStyle(.plain)
        }
        if let e = m.error { Text(e).font(.caption).foregroundStyle(Theme.hot) }
      }
    }
  }
}

struct MainView: View {
  @EnvironmentObject var m: Model

  private var statusLine: String {
    guard m.helperUp else { return "Helper not installed" }
    switch m.choice {
    case .auto: return "Automatic"
    case .hold: return "Holding \(Int(m.lo))–\(Int(m.hi))°"
    case .fixed: return "Manual · \(Int(m.fixedRpm)) rpm"
    }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      HStack {
        Caption("FAN CONTROL")
        Spacer()
        Circle().fill(m.helperUp ? Theme.accent : Theme.amber).frame(width: 7, height: 7)
        Text(m.helperUp ? "Helper on" : "Helper off").font(.caption).foregroundStyle(Theme.dim)
      }

      HStack(alignment: .center) {
        VStack(alignment: .leading, spacing: 2) {
          Caption("CHIP TEMPERATURE")
          HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(m.temp.map { String(format: "%.0f", $0) } ?? "--")
              .font(.system(size: 92, weight: .thin, design: .rounded)).monospacedDigit().foregroundStyle(m.tempColor)
            Text("°C").font(.system(size: 26, weight: .light, design: .rounded)).foregroundStyle(Theme.dim)
          }
          Text(statusLine).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.dim)
        }
        Spacer()
        VStack(spacing: 8) {
          SpinningFan(rpm: Double(m.rpm), color: m.tempColor)
          Text("\(Int(m.rpm))").font(.system(size: 24, weight: .medium, design: .rounded)).monospacedDigit()
          Caption("RPM")
        }
        .frame(width: 96)
      }

      Panel {
        Chart {
          if m.choice == .hold && m.helperUp {
            RectangleMark(yStart: .value("lo", m.lo), yEnd: .value("hi", m.hi)).foregroundStyle(Theme.accent.opacity(0.14))
          }
          RuleMark(y: .value("limit", 95)).foregroundStyle(Theme.hot.opacity(0.5)).lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 4]))
          ForEach(m.history) {
            AreaMark(x: .value("t", $0.t), yStart: .value("base", 30), yEnd: .value("°C", $0.temp))
              .foregroundStyle(LinearGradient(colors: [m.tempColor.opacity(0.28), .clear], startPoint: .top, endPoint: .bottom))
              .interpolationMethod(.monotone)
            LineMark(x: .value("t", $0.t), y: .value("°C", $0.temp)).foregroundStyle(m.tempColor).interpolationMethod(.monotone)
          }
        }
        .chartYScale(domain: 30...100).chartXAxis(.hidden)
        .chartYAxis {
          AxisMarks(position: .trailing, values: [40, 60, 80, 100]) {
            AxisGridLine().foregroundStyle(Theme.line)
            AxisValueLabel().foregroundStyle(Theme.dim)
          }
        }
        .chartPlotStyle { $0.clipped() }
        .frame(height: 140)
      }

      ControlPanel()
    }
    .padding(28)
    .frame(width: 440)
    .background(Theme.bg)
    .foregroundStyle(Color.white.opacity(0.92))
    .preferredColorScheme(.dark)
  }
}

struct MenuContent: View {
  @EnvironmentObject var m: Model
  @Environment(\.openWindow) private var openWindow
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text(m.temp.map { String(format: "%.0f°C", $0) } ?? "--").font(.system(size: 28, weight: .semibold, design: .rounded)).foregroundStyle(m.tempColor)
        Spacer()
        Label("\(Int(m.rpm)) rpm", systemImage: "fan").foregroundStyle(Theme.dim).monospacedDigit()
      }
      if m.helperUp { ModePicker() }
      Button("Open Fan Control") { openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true) }.buttonStyle(.plain)
      Button("Quit") { NSApp.terminate(nil) }.buttonStyle(.plain).foregroundStyle(Theme.dim)
    }
    .padding(16).frame(width: 270).foregroundStyle(Color.white.opacity(0.92)).preferredColorScheme(.dark)
  }
}

#if !PREVIEW
@main
struct FanControlApp: App {
  @StateObject private var model = Model()
  var body: some Scene {
    Window("Fan Control", id: "main") { MainView().environmentObject(model) }
      .windowStyle(.hiddenTitleBar)
      .windowResizability(.contentSize)
    MenuBarExtra {
      MenuContent().environmentObject(model)
    } label: {
      HStack(spacing: 3) { Image(systemName: "fan"); Text(model.menuTitle).monospacedDigit() }
    }
    .menuBarExtraStyle(.window)
  }
}
#endif
