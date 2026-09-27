import Foundation
import Observation

/// User settings, backed by UserDefaults. Everything stays on this Mac.
@Observable
final class Preferences {
  @ObservationIgnored private let defaults: UserDefaults

  /// Seconds before an icon moved out from under the notch goes back to its place.
  var autoHideDelay: Double { didSet { defaults.set(autoHideDelay, forKey: Key.autoHideDelay) } }
  var showCount: Bool { didSet { defaults.set(showCount, forKey: Key.showCount) } }
  var searchShortcut: Shortcut? { didSet { store(searchShortcut, Key.searchShortcut) } }
  var onboarded: Bool { didSet { defaults.set(onboarded, forKey: Key.onboarded) } }
  /// h j k l move in settings, next to the arrow keys.
  var vimKeys: Bool { didSet { defaults.set(vimKeys, forKey: Key.vimKeys) } }
  /// Open the dropdown in the middle of the screen instead of under the mark.
  var centered: Bool { didSet { defaults.set(centered, forKey: Key.centered) } }

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    defaults.register(defaults: [
      Key.autoHideDelay: 10.0, Key.showCount: true, Key.onboarded: false, Key.vimKeys: true,
      Key.centered: false,
    ])
    autoHideDelay = defaults.double(forKey: Key.autoHideDelay)
    showCount = defaults.bool(forKey: Key.showCount)
    onboarded = defaults.bool(forKey: Key.onboarded)
    vimKeys = defaults.bool(forKey: Key.vimKeys)
    centered = defaults.bool(forKey: Key.centered)
    searchShortcut = Self.load(defaults, Key.searchShortcut, fallback: .defaultSearch)
  }

  private func store(_ shortcut: Shortcut?, _ key: String) {
    // An explicit "none" is stored as empty data so it doesn't fall back to the default.
    defaults.set(shortcut.flatMap { try? JSONEncoder().encode($0) } ?? Data(), forKey: key)
  }

  private static func load(_ defaults: UserDefaults, _ key: String, fallback: Shortcut) -> Shortcut? {
    guard let data = defaults.data(forKey: key) else { return fallback }
    return try? JSONDecoder().decode(Shortcut.self, from: data)
  }

  enum Key {
    static let autoHideDelay = "autoHideDelay"
    static let showCount = "showCount"
    static let searchShortcut = "searchShortcut"
    static let onboarded = "onboarded"
    static let vimKeys = "vimKeys"
    static let centered = "centered"
    static let usage = "usage"
  }
}
