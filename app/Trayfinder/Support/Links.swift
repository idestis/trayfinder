import Foundation

/// Every URL the app can open. Opening one hands it to the browser; the app itself never fetches them.
nonisolated enum Links {
  static let repo = URL(string: "https://github.com/idestis/trayfinder")!
  static let site = URL(string: "https://idestis.github.io/trayfinder/")!
  static let releases = URL(string: "https://github.com/idestis/trayfinder/releases")!
  static let issues = URL(string: "https://github.com/idestis/trayfinder/issues")!
  static let united24 = URL(string: "https://u24.gov.ua/")!
  static let author = URL(string: "https://www.linkedin.com/in/dmytroshamenko/")!
  /// Apple's per-app menu bar toggles (Control Center pane, called Menu Bar on macOS 26 and later).
  static let menuBarSettings = URL(string: "x-apple.systempreferences:com.apple.ControlCenter-Settings.extension")!
  static let accessibilitySettings = URL(
    string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
}
