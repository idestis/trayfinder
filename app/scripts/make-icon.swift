// Renders AppIcon.appiconset from code, matching landing/logo.svg (lens with three dots).
//   swift scripts/make-icon.swift Trayfinder/Resources/Assets.xcassets/AppIcon.appiconset
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "AppIcon.appiconset")
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func render(_ px: Int) -> Data {
  let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
    hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
  let s = CGFloat(px) / 1024
  let ctx = NSGraphicsContext.current!.cgContext
  ctx.scaleBy(x: s, y: s)

  // macOS icon grid: 824pt squircle centred in 1024.
  let tile = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 185, yRadius: 185)
  // Flat indigo, with only a faint top light so it doesn't look pasted on.
  NSGradient(
    starting: NSColor(calibratedRed: 0.29, green: 0.36, blue: 0.93, alpha: 1),
    ending: NSColor(calibratedRed: 0.24, green: 0.30, blue: 0.86, alpha: 1))!.draw(in: tile, angle: -90)

  // Lens: logo.svg's 32-unit grid mapped onto the tile (y flipped).
  let u: CGFloat = 824 / 32 * 0.78
  let ox: CGFloat = 512 - 15.75 * u  // content spans 4.5…27, centre 15.75
  let oy: CGFloat = 512 + 15.75 * u
  func p(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: ox + x * u, y: oy - y * u) }
  NSColor.white.set()
  let ring = NSBezierPath(ovalIn: NSRect(x: p(4.5, 0).x, y: p(0, 22.5).y, width: 18 * u, height: 18 * u))
  ring.lineWidth = 2.6 * u
  ring.stroke()
  let handle = NSBezierPath()
  handle.move(to: p(20.3, 20.3))
  handle.line(to: p(27, 27))
  handle.lineWidth = 3 * u
  handle.lineCapStyle = .round
  handle.stroke()
  for cx in [9.5, 13.5, 17.5] as [CGFloat] {
    let c = p(cx, 13.5)
    NSBezierPath(ovalIn: NSRect(x: c.x - 1.6 * u, y: c.y - 1.6 * u, width: 3.2 * u, height: 3.2 * u)).fill()
  }
  NSGraphicsContext.restoreGraphicsState()
  return rep.representation(using: .png, properties: [:])!
}

var images: [String] = []
for pt in [16, 32, 128, 256, 512] {
  for scale in [1, 2] {
    let name = "icon_\(pt)x\(pt)\(scale == 2 ? "@2x" : "").png"
    try render(pt * scale).write(to: out.appendingPathComponent(name))
    images.append(
      #"{ "idiom" : "mac", "scale" : "\#(scale)x", "size" : "\#(pt)x\#(pt)", "filename" : "\#(name)" }"#)
  }
}
let json = "{\n  \"images\" : [\n    \(images.joined(separator: ",\n    "))\n  ],\n  \"info\" : { \"author\" : \"xcode\", \"version\" : 1 }\n}\n"
try json.write(to: out.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
print("wrote \(images.count) images to \(out.path)")
