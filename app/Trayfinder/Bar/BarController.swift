import AppKit

/// Trayfinder's one status item, the mark. It should be the rightmost app icon, next to Apple's system icons:
/// macOS moves icons behind its « overflow arrow from the left first, so that spot is never hidden.
/// Favourites sit immediately left of it.
final class BarController: NSObject {
  struct Actions {
    var search: () -> Void
    var settings: () -> Void
    var about: () -> Void
    var checkForUpdates: (() -> Void)?
  }

  private static let markName = "trayfinder.mark"

  private let mark: NSStatusItem
  private let actions: Actions

  /// Current search shortcut, shown in the mark's menu.
  var searchShortcut: () -> Shortcut? = { nil }

  init(actions: Actions) {
    self.actions = actions
    // First launch: ask for the rightmost spot. macOS doesn't always honour it; TrayModel checks and fixes it.
    let key = "NSStatusItem Preferred Position \(Self.markName)"
    if UserDefaults.standard.object(forKey: key) == nil { UserDefaults.standard.set(0.0, forKey: key) }
    mark = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    mark.autosaveName = Self.markName
    super.init()

    if let button = mark.button {
      button.image = Mark.image
      button.imagePosition = .imageLeading
      button.setAccessibilityLabel(String(localized: "Trayfinder"))
      button.target = self
      button.action = #selector(markClicked)
      button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }
  }

  // MARK: Geometry (x is shared by Cocoa and Accessibility: both measure from the primary screen's left edge)

  /// The mark's frame in Cocoa screen coordinates, for anchoring the dropdown.
  var markFrame: NSRect? { mark.button?.window?.frame }
  var markScreen: NSScreen? { mark.button?.window?.screen }
  var markMinX: CGFloat? { markFrame?.minX }
  /// The mark's frame in Accessibility coordinates (top-left origin), for dragging it.
  var markAXFrame: CGRect? {
    guard let f = markFrame, let primary = NSScreen.screens.first else { return nil }
    return CGRect(x: f.minX, y: primary.frame.maxY - f.maxY, width: f.width, height: f.height)
  }

  func setHighlighted(_ on: Bool) { mark.button?.highlight(on) }

  func setCount(_ n: Int) { mark.button?.title = n > 0 ? "+\(n)" : "" }

  // MARK: Clicks

  @objc private func markClicked() {
    let event = NSApp.currentEvent
    if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
      showMenu()
    } else {
      actions.search()
    }
  }

  private func showMenu() {
    let menu = NSMenu()
    menu.autoenablesItems = false
    menu.addItem(
      item(String(localized: "Search menu bar…"), shortcut: searchShortcut()) { [actions] in actions.search() })
    menu.addItem(item(String(localized: "Settings…"), key: ",") { [actions] in actions.settings() })
    menu.addItem(.separator())
    let update = item(String(localized: "Check for updates…")) { [actions] in actions.checkForUpdates?() }
    update.isEnabled = actions.checkForUpdates != nil
    menu.addItem(update)
    menu.addItem(item(String(localized: "About Trayfinder")) { [actions] in actions.about() })
    menu.addItem(.separator())
    menu.addItem(item(String(localized: "Quit Trayfinder"), key: "q") { NSApp.terminate(nil) })
    mark.menu = menu
    mark.button?.performClick(nil)
    mark.menu = nil
  }

  private func item(_ title: String, key: String = "", shortcut: Shortcut? = nil, _ run: @escaping () -> Void)
    -> NSMenuItem
  {
    let item = NSMenuItem(title: title, action: #selector(MenuTarget.fire(_:)), keyEquivalent: key)
    if let shortcut, let equivalent = Self.keyEquivalent(shortcut) {
      item.keyEquivalent = equivalent
      item.keyEquivalentModifierMask = Self.modifierFlags(shortcut)
    }
    item.target = MenuTarget.shared
    item.representedObject = MenuTarget.Action(run)
    return item
  }

  /// Menu key equivalent for a global shortcut, so the menu shows it (the menu never fires it; Carbon does).
  private static func keyEquivalent(_ s: Shortcut) -> String? {
    switch Int(s.keyCode) {
    case 0x31: return " "
    case 0x24: return "\r"
    default:
      let name = Shortcut.keyName(s.keyCode)
      return name.count == 1 ? name.lowercased() : nil
    }
  }

  private static func modifierFlags(_ s: Shortcut) -> NSEvent.ModifierFlags {
    var f: NSEvent.ModifierFlags = []
    if s.modifiers & 0x1000 != 0 { f.insert(.control) }
    if s.modifiers & 0x0800 != 0 { f.insert(.option) }
    if s.modifiers & 0x0200 != 0 { f.insert(.shift) }
    if s.modifiers & 0x0100 != 0 { f.insert(.command) }
    return f
  }
}

/// Runs the closure stored in a menu item's `representedObject`.
private final class MenuTarget: NSObject {
  static let shared = MenuTarget()

  final class Action {
    let run: () -> Void
    init(_ run: @escaping () -> Void) { self.run = run }
  }

  @objc func fire(_ sender: NSMenuItem) { (sender.representedObject as? Action)?.run() }
}

/// Detects an open menu or popover, so a moved icon isn't taken away from under it.
enum MenuWatcher {
  /// Any pop-up menu on screen, or (with `pid`) any window of that app above normal level, such as a popover.
  static func isOpen(pid: pid_t?) -> Bool {
    guard
      let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
        as? [[String: Any]]
    else { return false }
    let menuLevel = Int(CGWindowLevelForKey(.popUpMenuWindow))
    let statusLevel = Int(CGWindowLevelForKey(.statusWindow))
    return list.contains { w in
      let layer = w[kCGWindowLayer as String] as? Int ?? 0
      if layer == menuLevel { return true }
      guard let pid, (w[kCGWindowOwnerPID as String] as? pid_t) == pid else { return false }
      return layer > 0 && layer != statusLevel
    }
  }
}
