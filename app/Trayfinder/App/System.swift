import AppKit
import ServiceManagement
import Sparkle

/// Open at login through SMAppService; the system owns the truth.
enum LoginItem {
  static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

  static func set(_ on: Bool) {
    do {
      if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
    } catch {
      Log.make("login").error("login item: \(error.localizedDescription, privacy: .public)")
    }
  }
}

/// Starts a fresh copy of the app and quits this one. macOS can need this before a new
/// Accessibility grant reaches a process that was already running.
enum Relaunch {
  static func now() {
    let config = NSWorkspace.OpenConfiguration()
    config.createsNewApplicationInstance = true
    NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: config) { _, _ in
      DispatchQueue.main.async { NSApp.terminate(nil) }
    }
  }
}

/// Sparkle, the only code that touches the network. Off when the build has no public key.
final class Updater {
  private let controller: SPUStandardUpdaterController?

  init() {
    let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String ?? ""
    controller =
      key.isEmpty
      ? nil : SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
  }

  var isAvailable: Bool { controller != nil }

  var checksAutomatically: Bool {
    get { controller?.updater.automaticallyChecksForUpdates ?? false }
    set { controller?.updater.automaticallyChecksForUpdates = newValue }
  }

  func checkForUpdates() {
    NSApp.activate()
    controller?.checkForUpdates(nil)
  }
}
