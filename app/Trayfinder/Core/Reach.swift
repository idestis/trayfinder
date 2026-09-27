import CoreGraphics

/// Where a menu bar item is, as far as the user can reach it.
nonisolated enum Reach: Equatable, Sendable {
  case visible
  /// Behind macOS's « overflow arrow (Accessibility reports it off-screen, at x ≈ -1, or with no width).
  case overflow
  /// Laid out, but under the camera notch.
  case notch

  /// `notch` is the horizontal range the notch covers on the item's screen, if it has one.
  static func of(_ frame: CGRect, notch: ClosedRange<CGFloat>?) -> Reach {
    if frame.width <= 0 || frame.maxX <= 0 || frame.minX < 0 { return .overflow }
    if let notch, frame.maxX > notch.lowerBound, frame.minX < notch.upperBound { return .notch }
    return .visible
  }
}
