// Generates AppIcon.icns (fan glyph on a gradient tile). Run once: swift make-icon.swift
import AppKit

func png(_ px: Int) -> Data {
  let img = NSImage(size: NSSize(width: px, height: px), flipped: false) { r in
    let tile = NSBezierPath(roundedRect: r.insetBy(dx: CGFloat(px) * 0.05, dy: CGFloat(px) * 0.05), xRadius: CGFloat(px) * 0.22, yRadius: CGFloat(px) * 0.22)
    NSGradient(colors: [NSColor(red: 0.05, green: 0.2, blue: 0.35, alpha: 1), NSColor(red: 0.1, green: 0.6, blue: 0.7, alpha: 1)])!.draw(in: tile, angle: -60)
    let cfg = NSImage.SymbolConfiguration(pointSize: CGFloat(px) * 0.55, weight: .regular).applying(.init(paletteColors: [.white]))
    if let g = NSImage(systemSymbolName: "fan.fill", accessibilityDescription: nil)?.withSymbolConfiguration(cfg) {
      let s = g.size
      g.draw(in: NSRect(x: (r.width - s.width) / 2, y: (r.height - s.height) / 2, width: s.width, height: s.height))
    }
    return true
  }
  let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
  return rep.representation(using: .png, properties: [:])!
}

let dir = "AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
for (name, px) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128), ("128x128@2x", 256),
                   ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)] {
  try! png(px).write(to: URL(fileURLWithPath: "\(dir)/icon_\(name).png"))
}
