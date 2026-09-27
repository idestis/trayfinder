import AppKit
import Carbon.HIToolbox
import Observation

/// Settings as a keyboard-first list: j k (or arrows) choose, ↵ or l changes, h or esc goes back.
/// Every key goes through `handle(_:)`; the view only draws `rows`.
@Observable
final class SettingsModel {
  enum Page: Equatable { case root, favourites, about }

  struct Row: Identifiable {
    enum Kind { case value, shortcut(HotKeys.Action), page, link, info }
    let id: String
    var section: String?
    let label: String
    var value: String = ""
    var accent = false
    var item: MenuBarItem?
    let kind: Kind
    var run: () -> Void = {}
  }

  private(set) var page: Page = .root
  var selection = 0
  private(set) var query = ""
  private(set) var searching = false
  /// The shortcut being recorded, if any. The panel sends the next key press to `record(_:)`.
  private(set) var recording: HotKeys.Action?
  private(set) var openAtLogin = LoginItem.isEnabled
  private(set) var trusted = AX.isTrusted(prompt: false)
  /// Mirrors Sparkle's setting so the row redraws when it changes.
  private(set) var autoCheck = false

  @ObservationIgnored let prefs: Preferences
  @ObservationIgnored let tray: TrayModel
  @ObservationIgnored let updater: Updater
  @ObservationIgnored var onClose: () -> Void = {}
  @ObservationIgnored var applyShortcuts: () -> Void = {}
  @ObservationIgnored var pauseShortcuts: () -> Void = {}

  init(prefs: Preferences, tray: TrayModel, updater: Updater) {
    self.prefs = prefs
    self.tray = tray
    self.updater = updater
    autoCheck = updater.checksAutomatically
  }

  var vimKeys: Bool { prefs.vimKeys }

  var title: String {
    switch page {
    case .root: String(localized: "Settings")
    case .favourites: String(localized: "Favourites")
    case .about: String(localized: "About")
    }
  }

  // MARK: Rows

  var rows: [Row] {
    switch page {
    case .root: rootRows
    case .favourites: favouriteRows
    case .about: aboutRows
    }
  }

  private var rootRows: [Row] {
    var rows: [Row] = []
    let general = String(localized: "General")
    if !trusted {
      rows.append(
        Row(
          id: "ax", section: general, label: String(localized: "Accessibility access required"),
          value: String(localized: "Allow ›"), accent: true, kind: .page,
          run: { [weak self] in self?.askAccessibility() }))
    }
    if trusted, tray.needsRestart {
      rows.append(
        Row(
          id: "restart", section: general, label: String(localized: "Access granted, restart to finish"),
          value: String(localized: "Restart ›"), accent: true, kind: .page, run: { Relaunch.now() }))
    }
    let first = rows.isEmpty
    rows += [
      Row(
        id: "login", section: first ? general : nil, label: String(localized: "Open at login"),
        value: onOff(openAtLogin), accent: openAtLogin, kind: .value,
        run: { [weak self] in self?.toggleLogin() }),
      Row(
        id: "mark", label: String(localized: "Menu bar mark"),
        value: prefs.showCount ? String(localized: "Mark + count") : String(localized: "Mark only"), kind: .value,
        run: { [weak self] in
          guard let self else { return }
          self.prefs.showCount.toggle()
          self.tray.updateCount()
        }),
      Row(
        id: "keys", label: String(localized: "Keys"),
        value: prefs.vimKeys ? String(localized: "Arrow keys and h j k l") : String(localized: "Arrow keys only"),
        kind: .value, run: { [weak self] in self?.prefs.vimKeys.toggle() }),
      Row(
        id: "position", label: String(localized: "Position"),
        value: prefs.centered ? String(localized: "Center of screen") : String(localized: "Under the mark"),
        kind: .value, run: { [weak self] in self?.prefs.centered.toggle() }),
    ]

    let bar = String(localized: "Menu bar")
    rows += [
      Row(
        id: "favourites", section: bar, label: String(localized: "Favourites"), value: favouriteSummary, kind: .page,
        run: { [weak self] in self?.go(.favourites) }),
      Row(
        id: "delay", label: String(localized: "Move icons back after"), value: delayLabel(prefs.autoHideDelay),
        kind: .value, run: { [weak self] in self?.cycleDelay() }),
      Row(
        id: "apple", label: String(localized: "Hide icons for good"), value: String(localized: "System Settings ↗"),
        kind: .link, run: { NSWorkspace.shared.open(Links.menuBarSettings) }),
    ]

    let keys = String(localized: "Shortcuts")
    rows += [
      shortcutRow(.search, section: keys, label: String(localized: "Search menu bar"), prefs.searchShortcut),
      Row(id: "k-pin", label: String(localized: "Favourite selected icon"), value: "⌘P", kind: .info),
      Row(id: "k-open", label: String(localized: "Open result"), value: "⌘1…9", kind: .info),
      Row(id: "k-settings", label: String(localized: "Settings"), value: "⌘,", kind: .info),
    ]

    if updater.isAvailable {
      rows += [
        Row(
          id: "auto", section: String(localized: "Updates"), label: String(localized: "Check automatically"),
          value: onOff(autoCheck), accent: autoCheck, kind: .value,
          run: { [weak self] in self?.toggleAutoUpdate() }),
        Row(
          id: "check", label: String(localized: "Check for updates"), value: "›", kind: .page,
          run: { [weak self] in self?.updater.checkForUpdates() }),
      ]
    }
    rows.append(
      Row(
        id: "about", section: String(localized: "Trayfinder"), label: String(localized: "About and Support Ukraine"),
        value: "›", kind: .page, run: { [weak self] in self?.go(.about) }))
    return rows
  }

  private var favouriteRows: [Row] {
    let q = query.trimmingCharacters(in: .whitespaces)
    let items = q.isEmpty ? tray.items : tray.items.filter { Fuzzy.score($0.haystack, q) != nil }
    return items.map { item in
      let favourite = tray.isFavourite(item)
      return Row(
        id: item.id, label: item.title,
        value: favourite ? String(localized: "Next to Trayfinder") : String(localized: "Anywhere"),
        accent: favourite, item: item, kind: .value,
        run: { [weak self] in
          guard let self, !self.tray.isBusy else { return }
          Task { await self.tray.setFavourite(item, !favourite) }
        })
    }
  }

  /// About is drawn as a card; these are its selectable links, in reading order:
  /// three top links, the United24 donation, then the author credit.
  private var aboutRows: [Row] {
    func link(_ id: String, _ label: String, _ url: URL) -> Row {
      Row(id: id, label: label, kind: .link, run: { NSWorkspace.shared.open(url) })
    }
    return [
      link("repo", String(localized: "View source"), Links.repo),
      link("releases", String(localized: "What's new"), Links.releases),
      link("issues", String(localized: "Send feedback"), Links.issues),
      link("u24", String(localized: "Donate to United24"), Links.united24),
      link("author", String(localized: "Dmytro Shamenko"), Links.author),
    ]
  }

  var version: String {
    let info = Bundle.main.infoDictionary
    let v = info?["CFBundleShortVersionString"] as? String ?? "?"
    let b = info?["CFBundleVersion"] as? String ?? "?"
    return "\(v) (\(b))"
  }

  private func shortcutRow(_ action: HotKeys.Action, section: String?, label: String, _ shortcut: Shortcut?) -> Row {
    let value =
      recording == action ? String(localized: "Press keys…") : (shortcut?.display ?? String(localized: "None"))
    return Row(
      id: "sc-\(action.rawValue)", section: section, label: label, value: value, accent: recording == action,
      kind: .shortcut(action), run: { [weak self] in self?.startRecording(action) })
  }

  private var favouriteSummary: String {
    let names = tray.items.filter { tray.isFavourite($0) }.map(\.title)
    switch names.count {
    case 0: return String(localized: "None ›")
    case 1: return "\(names[0]) ›"
    default: return "\(names[0]), +\(names.count - 1) ›"
    }
  }

  private func onOff(_ on: Bool) -> String { on ? String(localized: "On") : String(localized: "Off") }

  private static let delays: [Double] = [5, 10, 30]

  private func delayLabel(_ d: Double) -> String {
    d == 0 ? String(localized: "Never") : String(localized: "\(Int(d)) seconds")
  }

  // MARK: Actions

  func reset() {
    page = .root
    selection = 0
    query = ""
    searching = false
    recording = nil
    openAtLogin = LoginItem.isEnabled
    trusted = AX.isTrusted(prompt: false)
  }

  func go(_ page: Page) {
    self.page = page
    selection = 0
    query = ""
    searching = false
    if page == .favourites { Task { await tray.refresh() } }
  }

  func activate(_ index: Int) {
    let rows = self.rows
    guard rows.indices.contains(index) else { return }
    selection = index
    rows[index].run()
  }

  private func toggleLogin() {
    LoginItem.set(!openAtLogin)
    openAtLogin = LoginItem.isEnabled
  }

  private func toggleAutoUpdate() {
    updater.checksAutomatically.toggle()
    autoCheck = updater.checksAutomatically
  }

  private func cycleDelay() {
    let i = Self.delays.firstIndex(of: prefs.autoHideDelay) ?? 0
    prefs.autoHideDelay = Self.delays[(i + 1) % Self.delays.count]
  }

  private func askAccessibility() {
    _ = AX.isTrusted(prompt: true)
    NSWorkspace.shared.open(Links.accessibilitySettings)
  }

  /// Called by the panel while it is open and permission is missing.
  func recheckTrust() async {
    guard !trusted, AX.isTrusted(prompt: false) else { return }
    trusted = true
    await tray.refresh()
  }

  // MARK: Recording

  private func startRecording(_ action: HotKeys.Action) {
    recording = action
    pauseShortcuts()
  }

  /// Takes the key press that follows ↵ on a shortcut row. esc cancels, ⌫ clears.
  func record(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
    guard let action = recording else { return }
    switch Int(keyCode) {
    case kVK_Escape:
      break
    case kVK_Delete, kVK_ForwardDelete:
      set(action, nil)
    default:
      let flags = modifiers.intersection(.deviceIndependentFlagsMask).rawValue
      let candidate = Shortcut(keyCode: UInt32(keyCode), modifiers: Shortcut.carbonModifiers(cocoa: flags))
      guard candidate.isValid else {
        NSSound.beep()
        return
      }
      set(action, candidate)
    }
    recording = nil
    applyShortcuts()
  }

  func cancelRecording() {
    guard recording != nil else { return }
    recording = nil
    applyShortcuts()
  }

  private func set(_ action: HotKeys.Action, _ shortcut: Shortcut?) {
    switch action {
    case .search: prefs.searchShortcut = shortcut
    }
  }

  // MARK: Keys

  enum Key {
    case up, down, left, right, change, back, close, startSearch, type(String), deleteBackward
  }

  func handle(_ key: Key) {
    let count = rows.count
    switch key {
    case .up: if count > 0 { selection = (selection - 1 + count) % count }
    case .down: if count > 0 { selection = (selection + 1) % count }
    case .left: if page == .about, count > 0 { selection = (selection - 1 + count) % count } else { handle(.back) }
    case .right: if page == .about, count > 0 { selection = (selection + 1) % count } else { activate(selection) }
    case .change: activate(selection)
    case .back:
      if searching || !query.isEmpty {
        query = ""
        searching = false
        selection = 0
      } else if page == .root {
        onClose()
      } else {
        let from = page
        go(.root)
        selection = rows.firstIndex { $0.id == (from == .about ? "about" : "favourites") } ?? 0
      }
    case .close: onClose()
    case .startSearch:
      guard page == .favourites else { return }
      searching = true
    case .type(let text):
      guard page == .favourites else { return }
      searching = true
      query += text
      selection = 0
    case .deleteBackward:
      guard !query.isEmpty else { return }
      query.removeLast()
      selection = 0
    }
  }

  var canSearch: Bool { page == .favourites }

  var hints: [(keys: [String], label: String)] {
    if recording != nil {
      return [(["⌫"], String(localized: "Clear")), (["esc"], String(localized: "Cancel"))]
    }
    let move = vimKeys ? ["j", "k"] : ["↑", "↓"]
    let back = vimKeys ? ["h"] : ["esc"]
    var hints: [(keys: [String], label: String)] = [
      (move, String(localized: "Choose")), (["↵"], String(localized: "Change")), (back, String(localized: "Back")),
    ]
    if canSearch { hints.append((vimKeys ? ["/"] : ["a–z"], String(localized: "Search"))) }
    return hints
  }
}
