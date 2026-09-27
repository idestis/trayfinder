import ApplicationServices
import CoreGraphics

/// Reads every app's `AXExtrasMenuBar`. Blocking; call off the main thread.
nonisolated enum MenuBarScanner {
  static let timeout: Float = 0.25

  static func scan(_ apps: [AppRef]) -> [MenuBarItem] {
    var out: [MenuBarItem] = []
    var seen = Set<String>()
    for app in apps {
      let appEl = AXUIElementCreateApplication(app.pid)
      AXUIElementSetMessagingTimeout(appEl, timeout)
      guard let bar = AX.element(appEl, "AXExtrasMenuBar") else { continue }
      let children = AX.elements(bar, kAXChildrenAttribute)
      for (i, child) in children.enumerated() {
        AXUIElementSetMessagingTimeout(child, timeout)
        let name =
          AX.string(child, kAXTitleAttribute)
          ?? AX.string(child, kAXDescriptionAttribute)
          ?? AX.string(child, kAXHelpAttribute)
          ?? (children.count > 1 ? "\(app.name) \(i + 1)" : app.name)
        var id = MenuBarItem.makeID(
          bundleID: app.bundleID, appName: app.name, identifier: AX.string(child, kAXIdentifierAttribute),
          index: i, count: children.count)
        // Two instances of one app (or two apps sharing a name) must not share rows, usage or pins.
        if seen.contains(id) { id += "#\(app.pid)" }
        seen.insert(id)
        out.append(
          MenuBarItem(
            id: id, name: name, appName: app.name, bundleID: app.bundleID, pid: app.pid,
            frame: AX.frame(child), element: child))
      }
    }
    return out.sorted { $0.frame.minX > $1.frame.minX }
  }

  /// Fresh frame for an item after the bar moved.
  static func frame(of item: MenuBarItem) -> CGRect { AX.frame(item.element) }

  /// Opens the item's real menu. A menu that starts tracking can make AXPress time out; that still counts.
  @discardableResult
  static func press(_ item: MenuBarItem) -> Bool {
    let result = AXUIElementPerformAction(item.element, kAXPressAction as CFString)
    return result == .success || result == .cannotComplete
  }
}

/// Thin Accessibility helpers.
nonisolated enum AX {
  static func isTrusted(prompt: Bool) -> Bool {
    let key = "AXTrustedCheckOptionPrompt"
    return AXIsProcessTrustedWithOptions([key: prompt] as CFDictionary)
  }

  static func value(_ el: AXUIElement, _ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(el, name as CFString, &value) == .success else { return nil }
    return value
  }

  static func string(_ el: AXUIElement, _ name: String) -> String? {
    guard let s = value(el, name) as? String, !s.isEmpty else { return nil }
    return s
  }

  static func element(_ el: AXUIElement, _ name: String) -> AXUIElement? {
    guard let v = value(el, name), CFGetTypeID(v) == AXUIElementGetTypeID() else { return nil }
    return (v as! AXUIElement)
  }

  static func elements(_ el: AXUIElement, _ name: String) -> [AXUIElement] {
    (value(el, name) as? [AXUIElement]) ?? []
  }

  static func frame(_ el: AXUIElement) -> CGRect {
    var origin = CGPoint.zero
    var size = CGSize.zero
    if let v = value(el, kAXPositionAttribute), CFGetTypeID(v) == AXValueGetTypeID() {
      AXValueGetValue(v as! AXValue, .cgPoint, &origin)
    }
    if let v = value(el, kAXSizeAttribute), CFGetTypeID(v) == AXValueGetTypeID() {
      AXValueGetValue(v as! AXValue, .cgSize, &size)
    }
    return CGRect(origin: origin, size: size)
  }
}
