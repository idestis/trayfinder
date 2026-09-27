import AppKit

/// Moves a menu bar item by simulating the ⌘-drag macOS supports for rearranging.
/// Needs Accessibility, which Trayfinder already has. The cursor returns to where it was.
nonisolated enum ItemMover {
  /// Drags from `from` to `to` (global, top-left origin).
  static func drag(from: CGPoint, to: CGPoint) {
    // A private source, so the user's real keys (a ⌘ still held from ⌘P) and mouse don't mix in.
    let source = CGEventSource(stateID: .privateState)
    let restore = CGEvent(source: nil)?.location
    // Detach the real mouse from the cursor for the duration, so a nudge can't drop the item early.
    CGAssociateMouseAndMouseCursorPosition(0)
    defer {
      CGAssociateMouseAndMouseCursorPosition(1)
      if let restore { CGWarpMouseCursorPosition(restore) }
    }

    func key(_ down: Bool) {
      guard let e = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: down) else { return }  // ⌘
      e.type = .flagsChanged
      e.flags = down ? .maskCommand : []
      e.post(tap: .cghidEventTap)
    }

    func mouse(_ type: CGEventType, _ point: CGPoint) {
      guard let e = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: .left)
      else { return }
      e.flags = .maskCommand
      if type == .leftMouseDown || type == .leftMouseUp { e.setIntegerValueField(.mouseEventClickState, value: 1) }
      e.post(tap: .cghidEventTap)
    }

    key(true)
    usleep(20_000)
    mouse(.mouseMoved, from)
    usleep(30_000)
    mouse(.leftMouseDown, from)
    usleep(120_000)
    let steps = 12
    for i in 1...steps {
      let t = CGFloat(i) / CGFloat(steps)
      mouse(.leftMouseDragged, CGPoint(x: from.x + (to.x - from.x) * t, y: from.y + (to.y - from.y) * t))
      usleep(12_000)
    }
    usleep(80_000)
    mouse(.leftMouseUp, to)
    usleep(40_000)
    key(false)
    usleep(40_000)
  }
}
