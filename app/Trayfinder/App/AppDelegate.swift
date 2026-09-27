import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
  private let prefs = Preferences()
  private let updater = Updater()
  private var bar: BarController?
  private var tray: TrayModel?
  private var palette: PaletteController?
  private var settings: SettingsPanel?
  private var hotKeys: HotKeys?

  func applicationDidFinishLaunching(_ notification: Notification) {
    // Unit tests run inside the app; don't touch the real menu bar from there.
    guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
    installMainMenu()

    let bar = BarController(
      actions: .init(
        search: { [weak self] in self?.palette?.toggle() },
        settings: { [weak self] in self?.settings?.show() },
        about: { [weak self] in self?.settings?.show(.about) },
        checkForUpdates: updater.isAvailable ? { [weak self] in self?.updater.checkForUpdates() } : nil))
    let tray = TrayModel(prefs: prefs, bar: bar)
    bar.searchShortcut = { [prefs] in prefs.searchShortcut }
    let paletteModel = PaletteModel(tray: tray)
    paletteModel.onSettings = { [weak self] in self?.settings?.show() }

    self.bar = bar
    self.tray = tray
    palette = PaletteController(model: paletteModel, bar: bar, prefs: prefs)
    settings = SettingsPanel(model: makeSettingsModel(tray: tray))
    hotKeys = HotKeys { [weak self] action in
      switch action {
      case .search: self?.palette?.toggle()
      }
    }
    applyShortcuts()

    let trusted = AX.isTrusted(prompt: false)
    if !prefs.onboarded || !trusted {
      settings?.show(trusted ? .favourites : .root)
      prefs.onboarded = true
    }
    // Status items only get their places a moment after launch; then make sure the mark is rightmost.
    Task {
      try? await Task.sleep(for: .milliseconds(500))
      await tray.refresh()
      await tray.ensureMarkRightmost()
    }
  }

  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    settings?.show()
    return false
  }

  private func makeSettingsModel(tray: TrayModel) -> SettingsModel {
    let model = SettingsModel(prefs: prefs, tray: tray, updater: updater)
    model.applyShortcuts = { [weak self] in self?.applyShortcuts() }
    model.pauseShortcuts = { [weak self] in self?.hotKeys?.unregisterAll() }
    return model
  }

  private func applyShortcuts() {
    hotKeys?.register([.search: prefs.searchShortcut])
  }

  /// An accessory app has no visible menu, but text fields need Edit commands for ⌘C, ⌘V and friends.
  private func installMainMenu() {
    let main = NSMenu()
    let appItem = NSMenuItem()
    appItem.submenu = NSMenu()
    appItem.submenu?.addItem(
      withTitle: String(localized: "Quit Trayfinder"), action: #selector(NSApplication.terminate(_:)),
      keyEquivalent: "q")
    main.addItem(appItem)

    let editItem = NSMenuItem()
    let edit = NSMenu(title: String(localized: "Edit"))
    edit.addItem(withTitle: String(localized: "Undo"), action: Selector(("undo:")), keyEquivalent: "z")
    edit.addItem(withTitle: String(localized: "Redo"), action: Selector(("redo:")), keyEquivalent: "Z")
    edit.addItem(.separator())
    edit.addItem(withTitle: String(localized: "Cut"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
    edit.addItem(withTitle: String(localized: "Copy"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
    edit.addItem(withTitle: String(localized: "Paste"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
    edit.addItem(
      withTitle: String(localized: "Select all"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
    editItem.submenu = edit
    main.addItem(editItem)
    NSApp.mainMenu = main
  }
}
