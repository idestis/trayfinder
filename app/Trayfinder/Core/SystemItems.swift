/// Apple's background agents own some menu bar items but have no user-facing name or icon.
nonisolated enum SystemItems {
  private static let known: [String: (name: String, symbol: String)] = [
    "com.apple.TextInputMenuAgent": ("Input sources", "keyboard"),
    "com.apple.controlcenter": ("Control Center", "switch.2"),
    "com.apple.systemuiserver": ("System menu", "menubar.rectangle"),
    "com.apple.Spotlight": ("Spotlight", "magnifyingglass"),
    "com.apple.Siri": ("Siri", "waveform"),
    "com.apple.notificationcenterui": ("Notification Center", "bell"),
    "com.apple.TextInputSwitcher": ("Input sources", "keyboard"),
    "com.apple.AirPlayUIAgent": ("AirPlay", "airplayvideo"),
    "com.apple.weather.menu": ("Weather", "cloud.sun"),
  ]

  static func name(_ bundleID: String?) -> String? { bundleID.flatMap { known[$0]?.name } }
  static func symbol(_ bundleID: String?) -> String? { bundleID.flatMap { known[$0]?.symbol } }
}
