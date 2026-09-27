import AppKit
import Carbon.HIToolbox
import SwiftUI

/// A borderless, non-activating panel hanging under the mark: it takes keys but never steals focus.
final class PaletteController: NSObject, NSWindowDelegate {
  let model: PaletteModel
  private let bar: BarController
  private var panel: KeyPanel?
  private var monitor: Any?
  private var focusToken = 0

  private let prefs: Preferences

  init(model: PaletteModel, bar: BarController, prefs: Preferences) {
    self.model = model
    self.bar = bar
    self.prefs = prefs
    super.init()
    model.onClose = { [weak self] in self?.hide() }
    model.onResultsChange = { [weak self] in self?.layout() }
  }

  var isVisible: Bool { panel?.isVisible == true }

  func toggle() { isVisible ? hide() : show() }

  func show() {
    let panel = self.panel ?? makePanel()
    self.panel = panel
    model.query = ""
    model.recompute()
    Task {
      await model.tray.refresh()
      model.recompute()
    }
    focusToken += 1
    panel.contentView = NSHostingView(rootView: PaletteView(model: model, focusToken: focusToken))
    layout()
    panel.makeKeyAndOrderFront(nil)
    bar.setHighlighted(!prefs.centered)
    installMonitor()
  }

  func hide() {
    guard let panel, panel.isVisible else { return }
    panel.orderOut(nil)
    bar.setHighlighted(false)
    if let monitor { NSEvent.removeMonitor(monitor) }
    monitor = nil
    // Drop the SwiftUI tree while hidden, but not inside the event that closed it (a row tap).
    DispatchQueue.main.async { [weak self] in
      guard let self, self.panel?.isVisible == false else { return }
      self.panel?.contentView = nil
    }
  }

  func windowDidResignKey(_ notification: Notification) {
    // A pin drag clicks another app's item and can steal key for a moment; take it back instead of closing.
    if model.isPinning {
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in self?.panel?.makeKey() }
      return
    }
    hide()
  }

  /// Under the mark (or centred on the pointer's screen), top edge fixed while the row count changes height.
  private func layout() {
    guard let panel else { return }
    let size = CGSize(width: PaletteView.width, height: PaletteView.height(rows: model.results.count))
    let pointerScreen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }
    let screen = (prefs.centered ? pointerScreen : bar.markScreen) ?? NSScreen.main
    let visible = screen?.visibleFrame ?? .zero
    let anchor =
      prefs.centered
      ? NSRect(x: visible.midX, y: visible.maxY - visible.height * 0.18, width: 0, height: 0)
      : bar.markFrame ?? NSRect(x: visible.midX, y: visible.maxY, width: 0, height: 0)
    let top = min(anchor.minY, visible.maxY) - 6
    let x = min(max(anchor.midX - size.width / 2, visible.minX + 8), visible.maxX - size.width - 8)
    let m = PanelShadow.margin
    panel.setFrame(
      NSRect(x: x - m, y: top - size.height - m, width: size.width + 2 * m, height: size.height + 2 * m), display: true)
  }

  private func makePanel() -> KeyPanel {
    let p = KeyPanel(
      contentRect: NSRect(x: 0, y: 0, width: PaletteView.width, height: PaletteView.height(rows: 1)),
      styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
      backing: .buffered, defer: true)
    p.isFloatingPanel = true
    p.level = .popUpMenu
    p.backgroundColor = .clear
    p.isOpaque = false
    p.hasShadow = false
    p.hidesOnDeactivate = false
    p.isReleasedWhenClosed = false
    p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
    p.delegate = self
    return p
  }

  private func installMonitor() {
    guard monitor == nil else { return }
    monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
      guard let self, e.window === self.panel, let key = Self.key(for: e) else { return e }
      return self.model.handle(key) ? nil : e
    }
  }

  private static func key(for e: NSEvent) -> PaletteModel.Key? {
    let cmd = e.modifierFlags.contains(.command)
    let ctrl = e.modifierFlags.contains(.control)
    switch Int(e.keyCode) {
    case kVK_DownArrow: return .down
    case kVK_UpArrow: return .up
    case kVK_Return, kVK_ANSI_KeypadEnter: return .open
    case kVK_Escape: return .close
    case kVK_ANSI_N where ctrl: return .down
    case kVK_ANSI_P where ctrl: return .up
    case kVK_ANSI_P where cmd: return .pin
    case kVK_ANSI_Comma where cmd: return .settings
    case kVK_ANSI_W where cmd: return .close
    default:
      if cmd, let n = Int(e.charactersIgnoringModifiers ?? ""), (1...9).contains(n) { return .openIndex(n - 1) }
      return nil
    }
  }
}

final class KeyPanel: NSPanel {
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { false }
}
