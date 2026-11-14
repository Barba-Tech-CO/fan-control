// Offscreen render of the main view to a PNG (no screen capture). Usage: preview <out.png> [auto|hold|fixed] [helper:0|1]
import SwiftUI
import AppKit

MainActor.assumeIsolated {
  let m = Model()
  let a = CommandLine.arguments
  m.choice = Choice(rawValue: (a.count > 2 ? a[2] : "hold").capitalized) ?? .hold
  m.helperUp = a.count > 3 ? a[3] == "1" : true; if a.count > 4 { m.error = "Install the app root-owned first: sudo cp -R FanControl.app /Applications/ && sudo chown -R root:wheel /Applications/FanControl.app" }
  m.temp = 83
  m.rpm = 3400
  let now = Date()
  m.history = (0..<180).map { i in
    let temp = 78 + 6 * sin(Double(i) / 18) + Double(i % 7) * 0.3
    return Sample(t: now.addingTimeInterval(Double(i - 180) * 2), temp: temp, rpm: 3000)
  }
  let r = ImageRenderer(content: MainView().environmentObject(m))
  r.scale = 2
  if let cg = r.cgImage {
    let data = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])!
    try! data.write(to: URL(fileURLWithPath: a[1]))
    print("wrote", a[1], cg.width, cg.height)
  } else { print("render failed") }
}
