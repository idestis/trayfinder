import AppKit
import Observation

/// What Trayfinder knows about the menu bar: the items, where each one is, favourites and usage.
/// It doesn't hide anything itself. It gets you to any item wherever macOS put it (behind the « overflow
/// arrow, under the notch) and keeps favourites next to the mark, where macOS overflows last.
/// Scans only on demand: dropdown opens, apps launch or quit, the frontmost app or the screens change.
@Observable
final class TrayModel {
  private(set) var items: [MenuBarItem] = []
  private(set) var usage: [String: Frecency]
  /// Favourite ids, oldest first. Each sits immediately left of the mark.
  private(set) var favourites: [String]
  private(set) var isBusy = false
  /// Accessibility state as of the last scan.
  private(set) var trusted = AX.isTrusted(prompt: false)

  @ObservationIgnored let prefs: Preferences
  @ObservationIgnored let bar: BarController
  @ObservationIgnored private let defaults: UserDefaults
  @ObservationIgnored private var observers: [NSObjectProtocol] = []
  @ObservationIgnored private var debounce: Task<Void, Never>?
  @ObservationIgnored private var generation = 0
  /// Items moved next to the mark to reach them (from under the notch), with the task that moves each back.
  @ObservationIgnored private var visiting: [String: Task<Void, Never>] = [:]
  @ObservationIgnored private var overflowArrow: MenuBarItem?
  @ObservationIgnored private let log = Log.make("tray")

  private static let agentBundle = "com.apple.MenuBarAgent"

  init(prefs: Preferences, bar: BarController, defaults: UserDefaults = .standard) {
    self.prefs = prefs
    self.bar = bar
    self.defaults = defaults
    usage = Self.decode(defaults.data(forKey: Preferences.Key.usage)) ?? [:]
    favourites = defaults.stringArray(forKey: Key.favourites) ?? []

    let ws = NSWorkspace.shared.notificationCenter
    for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
      observers.append(
        ws.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
          MainActor.assumeIsolated { self?.scheduleRefresh() }
        })
    }
    // The frontmost app's menus decide how much room icons get, so what's out of sight changes with it.
    observers.append(
      ws.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) {
        [weak self] _ in
        MainActor.assumeIsolated {
          guard let self, self.prefs.showCount else { return }
          self.scheduleRefresh(after: 0.4)
        }
      })
    observers.append(
      NotificationCenter.default.addObserver(
        forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
      ) { [weak self] _ in MainActor.assumeIsolated { self?.scheduleRefresh() } })
  }

  // MARK: Scanning

  /// Apps add their status items a moment after launch, so wait before looking.
  func scheduleRefresh(after seconds: Double = 1.5) {
    debounce?.cancel()
    debounce = Task { [weak self] in
      try? await Task.sleep(for: .seconds(seconds))
      guard !Task.isCancelled else { return }
      await self?.refresh()
    }
  }

  func refresh() async {
    let me = ProcessInfo.processInfo.processIdentifier
    let running = NSWorkspace.shared.runningApplications.filter {
      $0.processIdentifier != me && $0.processIdentifier > 0
    }
    func ref(_ app: NSRunningApplication) -> AppRef {
      AppRef(
        pid: app.processIdentifier, name: SystemItems.name(app.bundleIdentifier) ?? app.localizedName ?? "App",
        bundleID: app.bundleIdentifier)
    }
    // MenuBarAgent hosts Apple's own items (Wi-Fi, clock) as unnamed views, and the « overflow arrow.
    let apps = running.filter { $0.bundleIdentifier != Self.agentBundle }.map(ref)
    let agents = running.filter { $0.bundleIdentifier == Self.agentBundle }.map(ref)
    generation &+= 1
    let mine = generation
    let (scanned, system) = await Task.detached(priority: .userInitiated) {
      (MenuBarScanner.scan(apps), MenuBarScanner.scan(agents))
    }.value
    // A slower, older scan must not overwrite a newer one (its frames predate a move).
    guard mine == generation else { return }
    trusted = AX.isTrusted(prompt: false)
    items = scanned
    overflowArrow = Self.findOverflowArrow(system: system, apps: scanned)
    log.info("scan: trusted=\(self.trusted, privacy: .public) items=\(scanned.count, privacy: .public)")
    updateCount()
  }

  /// The « arrow is a narrow MenuBarAgent item left of every visible app icon.
  private static func findOverflowArrow(system: [MenuBarItem], apps: [MenuBarItem]) -> MenuBarItem? {
    let leftmost = apps.filter { Reach.of($0.frame, notch: nil) == .visible }.map(\.frame.minX).min() ?? .infinity
    return system.filter { $0.frame.width > 0 && $0.frame.width < 30 && $0.frame.maxX <= leftmost + 2 }
      .max { $0.frame.minX < $1.frame.minX }
  }

  /// Granted, yet nothing readable: the grant hasn't reached this process (or the build changed). Restart fixes it.
  var needsRestart: Bool { trusted && items.isEmpty }

  // MARK: Where things are

  func reach(_ item: MenuBarItem) -> Reach {
    let screen = NSScreen.screens.first { $0.frame.minX <= item.frame.midX && item.frame.midX < $0.frame.maxX }
    var notch: ClosedRange<CGFloat>?
    if let s = screen, let l = s.auxiliaryTopLeftArea, let r = s.auxiliaryTopRightArea, l.maxX < r.minX {
      notch = l.maxX...r.minX
    }
    return Reach.of(item.frame, notch: notch)
  }

  /// Items the user can't see right now: behind the « arrow or under the notch.
  var outOfSight: [MenuBarItem] { items.filter { reach($0) != .visible && visiting[$0.id] == nil } }

  func updateCount() { bar.setCount(prefs.showCount ? outOfSight.count : 0) }

  // MARK: The mark's place

  /// The mark belongs at the right end of the app icons. macOS doesn't always put it there; ⌘-drag it if not.
  func ensureMarkRightmost() async {
    guard trusted, !isBusy, let mark = bar.markAXFrame else { return }
    let right = items.filter { reach($0) == .visible && $0.frame.minX > mark.maxX }.max {
      $0.frame.minX < $1.frame.minX
    }
    guard let right else { return }
    isBusy = true
    defer { isBusy = false }
    log.info("moving the mark right of \(right.id, privacy: .public)")
    let from = CGPoint(x: mark.midX, y: mark.midY)
    let to = CGPoint(x: right.frame.maxX - 3, y: mark.midY)
    await Task.detached { ItemMover.drag(from: from, to: to) }.value
    try? await Task.sleep(for: .milliseconds(300))
    await refresh()
  }

  // MARK: Favourites

  func isFavourite(_ item: MenuBarItem) -> Bool { favourites.contains(item.id) }

  /// A favourite is ⌘-dragged to just left of the mark; removing one drags it left of the other favourites.
  @discardableResult
  func setFavourite(_ item: MenuBarItem, _ on: Bool) async -> Bool {
    guard isFavourite(item) != on, !isBusy else { return isFavourite(item) == on }
    isBusy = true
    defer {
      isBusy = false
      updateCount()
    }
    visiting.removeValue(forKey: item.id)?.cancel()
    if on {
      favourites.append(item.id)
    } else {
      favourites.removeAll { $0 == item.id }
    }
    defaults.set(favourites, forKey: Key.favourites)
    await refresh()
    guard trusted, let fresh = items.first(where: { $0.id == item.id }), reach(fresh) != .overflow else {
      return true  // kept as a favourite in the list; it moves next time it's reachable
    }
    let target: CGFloat?
    if on {
      target = bar.markMinX.map { $0 - 3 }
    } else {
      // Left of the leftmost remaining favourite, so it leaves the group; no other favourites: leave it.
      let others = items.filter { favourites.contains($0.id) && reach($0) == .visible }
      target = others.map(\.frame.minX).min().map { $0 + 2 }
    }
    guard let target else { return true }
    return await drag(fresh, to: target)
  }

  private func drag(_ item: MenuBarItem, to x: CGFloat) async -> Bool {
    let from = CGPoint(x: item.frame.midX, y: item.frame.midY)
    let to = CGPoint(x: x, y: item.frame.midY)
    let before = item.frame.minX
    await Task.detached { ItemMover.drag(from: from, to: to) }.value
    try? await Task.sleep(for: .milliseconds(300))
    await refresh()
    let moved = items.first { $0.id == item.id }.map { abs($0.frame.minX - before) > 4 } ?? false
    if !moved { log.error("move: \(item.id, privacy: .public) did not move") }
    return moved
  }

  // MARK: Open

  /// Opens the item's real menu wherever it is:
  /// visible: press it; behind the « arrow: expand the arrow, then press it in place;
  /// under the notch: move it next to the mark, press it, and move it back after the delay.
  func open(_ item: MenuBarItem) async {
    usage[item.id] = (usage[item.id] ?? Frecency(score: 0, at: Date().timeIntervalSince1970)).bumped(now: Date())
    save(usage, Preferences.Key.usage)
    try? await Task.sleep(for: .milliseconds(80))  // let the dropdown fade first

    switch reach(item) {
    case .visible:
      press(item)
    case .overflow:
      await openFromOverflow(item)
    case .notch:
      if !(await visit(item)) { press(item) }
    }
  }

  /// AXPress can block while the target app tracks its menu, so don't wait for it.
  private func press(_ item: MenuBarItem) {
    Task.detached(priority: .userInitiated) { MenuBarScanner.press(item) }
  }

  private func openFromOverflow(_ item: MenuBarItem) async {
    if let arrow = overflowArrow {
      press(arrow)
      try? await Task.sleep(for: .milliseconds(350))
      await refresh()
      if let fresh = items.first(where: { $0.id == item.id }), reach(fresh) == .visible {
        press(fresh)
        return
      }
      log.info("overflow arrow didn't reveal \(item.id, privacy: .public); pressing it where it is")
    }
    // Still works; the menu just opens at the screen's corner instead of under the icon.
    press(item)
  }

  /// Moves an item from under the notch to just left of the mark and opens it there.
  private func visit(_ item: MenuBarItem) async -> Bool {
    guard !isBusy, let markMinX = bar.markMinX else { return false }
    // Remember its right-hand neighbour, to put it back in the same place.
    let neighbour = items.filter { $0.frame.minX > item.frame.maxX - 1 && $0.id != item.id }
      .min { $0.frame.minX < $1.frame.minX }
    isBusy = true
    let moved = await drag(item, to: markMinX - 3)
    isBusy = false
    guard moved, let fresh = items.first(where: { $0.id == item.id }) else { return false }
    press(fresh)
    visiting[item.id] = returnLater(item, before: neighbour?.id)
    updateCount()
    return true
  }

  /// After the delay, and once its menu is closed, drags the item back left of its old neighbour.
  private func returnLater(_ item: MenuBarItem, before neighbourID: String?) -> Task<Void, Never> {
    let delay = max(prefs.autoHideDelay, 3)
    return Task { [weak self] in
      try? await Task.sleep(for: .seconds(delay))
      for _ in 0..<120 where !Task.isCancelled && MenuWatcher.isOpen(pid: item.pid) {
        try? await Task.sleep(for: .milliseconds(500))
      }
      for _ in 0..<40 where !Task.isCancelled && self?.isBusy == true {
        try? await Task.sleep(for: .milliseconds(250))
      }
      guard !Task.isCancelled, let self else { return }
      await self.refresh()
      defer { self.visiting.removeValue(forKey: item.id) }
      guard let fresh = self.items.first(where: { $0.id == item.id }),
        let neighbour = neighbourID.flatMap({ id in self.items.first { $0.id == id } })
      else { return }
      self.isBusy = true
      _ = await self.drag(fresh, to: neighbour.frame.minX + 2)
      self.isBusy = false
      self.updateCount()
    }
  }

  // MARK: Storage

  private enum Key {
    static let favourites = "favourites"
  }

  private func save<T: Encodable>(_ value: T, _ key: String) {
    defaults.set(try? JSONEncoder().encode(value), forKey: key)
  }

  private static func decode<T: Decodable>(_ data: Data?) -> T? {
    data.flatMap { try? JSONDecoder().decode(T.self, from: $0) }
  }
}
