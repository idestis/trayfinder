import ApplicationServices
import CoreGraphics

/// One menu bar extra owned by some app, as seen through Accessibility.
nonisolated struct MenuBarItem: Identifiable, Hashable, @unchecked Sendable {
  /// Stable key for usage and pins. Titles can change (clocks, counters), so it avoids them.
  let id: String
  let name: String
  let appName: String
  let bundleID: String?
  let pid: pid_t
  /// Global coordinates, top-left origin, as Accessibility reports them.
  let frame: CGRect
  let element: AXUIElement

  static func == (a: MenuBarItem, b: MenuBarItem) -> Bool { a.id == b.id && a.frame == b.frame }
  func hash(into h: inout Hasher) { h.combine(id) }

  /// Text the search matches against.
  var haystack: String { name == appName ? name : "\(appName) \(name)" }
  /// Row title: the app, which is what people remember.
  var title: String { appName }
  /// Row subtitle: the item's own text ("Connected", "3 unread"), when it says more than the app name.
  var subtitle: String? { name == appName ? nil : name }

  /// Builds the stable id: bundle id, plus the AX identifier or index when an app owns several items.
  static func makeID(bundleID: String?, appName: String, identifier: String?, index: Int, count: Int) -> String {
    let owner = bundleID ?? appName
    if let identifier, !identifier.isEmpty { return "\(owner)|\(identifier)" }
    return count > 1 ? "\(owner)|\(index)" : owner
  }
}

/// A running app worth asking for menu bar extras. Plain values so scanning can leave the main thread.
nonisolated struct AppRef: Sendable {
  let pid: pid_t
  let name: String
  let bundleID: String?
}
