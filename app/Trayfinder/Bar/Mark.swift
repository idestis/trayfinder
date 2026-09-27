import AppKit

/// Template images drawn in code: no assets to ship, crisp at any scale.
enum Mark {
  /// A lens with three dots, the Trayfinder mark.
  static let image: NSImage = {
    let img = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
      NSColor.black.set()
      let ring = NSBezierPath(ovalIn: NSRect(x: 2, y: 5, width: 11, height: 11))
      ring.lineWidth = 1.6
      ring.stroke()
      let handle = NSBezierPath()
      handle.move(to: NSPoint(x: 11.4, y: 6.4))
      handle.line(to: NSPoint(x: 16, y: 1.8))
      handle.lineWidth = 1.8
      handle.lineCapStyle = .round
      handle.stroke()
      for x in [4.9, 7.5, 10.1] {
        NSBezierPath(ovalIn: NSRect(x: x - 0.95, y: 9.55, width: 1.9, height: 1.9)).fill()
      }
      return true
    }
    img.isTemplate = true
    img.accessibilityDescription = String(localized: "Trayfinder")
    return img
  }()
}
