import AppKit
import Carbon.HIToolbox
import SwiftUI

/// A glass panel driven from the keyboard, like the dropdown. Opened rarely, so its views are released on close.
final class SettingsPanel: NSObject, NSWindowDelegate {
  static let size = CGSize(width: 540, height: 620)

  let model: SettingsModel
  private var panel: KeyPanel?
  private var monitor: Any?
  private var trustPoll: Task<Void, Never>?

  init(model: SettingsModel) {
    self.model = model
    super.init()
    model.onClose = { [weak self] in self?.hide() }
  }

  var isVisible: Bool { panel?.isVisible == true }

  func show(_ page: SettingsModel.Page = .root) {
    let panel = self.panel ?? makePanel()
    self.panel = panel
    model.reset()
    if page != .root { model.go(page) }
    Task { await model.tray.refresh() }
    panel.contentView = NSHostingView(rootView: SettingsPanelView(model: model))
    let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
    if let f = screen?.visibleFrame {
      let m = PanelShadow.margin
      let w = Self.size.width + 2 * m
      let h = min(Self.size.height, f.height - 40) + 2 * m
      panel.setFrame(NSRect(x: f.midX - w / 2, y: f.midY - h / 2 + f.height * 0.05, width: w, height: h), display: true)
    }
    panel.makeKeyAndOrderFront(nil)
    installMonitor()
    startTrustPoll()
  }

  func hide() {
    guard let panel, panel.isVisible else { return }
    model.cancelRecording()
    panel.orderOut(nil)
    if let monitor { NSEvent.removeMonitor(monitor) }
    monitor = nil
    trustPoll?.cancel()
    DispatchQueue.main.async { [weak self] in
      guard let self, self.panel?.isVisible == false else { return }
      self.panel?.contentView = nil
    }
  }

  func windowDidResignKey(_ notification: Notification) {
    // Pinning from the list drags another app's item and can take key for a moment.
    if model.tray.isBusy {
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in self?.panel?.makeKey() }
      return
    }
    hide()
  }

  /// Checks once a second, only while this panel is open and permission is missing.
  private func startTrustPoll() {
    trustPoll?.cancel()
    guard !model.trusted else { return }
    trustPoll = Task { [weak self] in
      while let self, !self.model.trusted, !Task.isCancelled {
        try? await Task.sleep(for: .seconds(1))
        await self.model.recheckTrust()
      }
    }
  }

  private func makePanel() -> KeyPanel {
    let p = KeyPanel(
      contentRect: NSRect(origin: .zero, size: Self.size),
      styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
      backing: .buffered, defer: true)
    p.isFloatingPanel = true
    p.level = .floating
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
      guard let self, e.window === self.panel else { return e }
      if self.model.recording != nil {
        self.model.record(keyCode: e.keyCode, modifiers: e.modifierFlags)
        return nil
      }
      guard let key = self.key(for: e) else { return nil }
      self.model.handle(key)
      return nil
    }
  }

  private func key(for e: NSEvent) -> SettingsModel.Key? {
    let flags = e.modifierFlags.intersection(.deviceIndependentFlagsMask)
    if flags.contains(.command) {
      switch Int(e.keyCode) {
      case kVK_ANSI_W, kVK_ANSI_Comma: return .close
      default: return nil
      }
    }
    let searching = model.searching || !model.query.isEmpty
    switch Int(e.keyCode) {
    case kVK_Escape: return .back
    case kVK_Return, kVK_ANSI_KeypadEnter: return .change
    case kVK_UpArrow: return .up
    case kVK_DownArrow: return .down
    case kVK_LeftArrow: return searching ? nil : .left
    case kVK_RightArrow: return searching ? nil : .right
    case kVK_Delete: return searching ? .deleteBackward : nil
    case kVK_Space where !searching: return .change
    default: break
    }
    guard !flags.contains(.control), let text = e.characters, !text.isEmpty,
      text.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) })
    else { return nil }
    if searching { return .type(text) }
    if model.vimKeys {
      switch text {
      case "j": return .down
      case "k": return .up
      case "l": return .change
      case "h": return .back
      case "/": return .startSearch
      default: break
      }
    }
    return model.canSearch ? .type(text) : nil
  }
}

// MARK: - Views

struct SettingsPanelView: View {
  @Bindable var model: SettingsModel

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      header.padding(.bottom, 14)
      if model.page == .about {
        AboutCard(model: model).frame(maxHeight: .infinity)
      } else {
        if model.canSearch { searchLine.padding(.bottom, 8) }
        list
      }
      footer.padding(.top, 12)
    }
    .padding(.horizontal, 22).padding(.vertical, 20)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .glassPanel(radius: 28)
    .panelShadow()
  }

  private var header: some View {
    HStack(spacing: 10) {
      Image(nsImage: Mark.image).resizable().frame(width: 20, height: 20)
      Text("trayfinder").font(.system(size: 18, weight: .bold))
      Text(model.title)
        .font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
        .padding(.horizontal, 10).padding(.vertical, 3)
        .background(.primary.opacity(0.07), in: Capsule())
      Spacer()
    }
  }

  private var searchLine: some View {
    HStack(spacing: 8) {
      Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
      if model.query.isEmpty {
        Text(model.vimKeys ? "Press / to search tray apps" : "Type to search tray apps")
          .foregroundStyle(.tertiary)
      } else {
        Text(model.query) + Text("▏").foregroundColor(.accentColor)
      }
      Spacer()
    }
    .font(.system(size: 14))
    .padding(.horizontal, 12).frame(height: 34)
    .background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
  }

  private var list: some View {
    let rows = model.rows
    return ScrollViewReader { proxy in
      ScrollView {
        VStack(alignment: .leading, spacing: 2) {
          if model.page == .favourites {
            Text("Tray apps open now · favourites stay next to Trayfinder, where macOS hides icons last")
              .font(.system(size: 12)).foregroundStyle(.secondary).padding(.horizontal, 12).padding(.bottom, 4)
          }
          ForEach(Array(rows.enumerated()), id: \.element.id) { i, row in
            if let section = row.section {
              Text(section).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                .padding(.horizontal, 12).padding(.top, i == 0 ? 0 : 14).padding(.bottom, 4)
            }
            SettingsRowView(row: row, selected: i == model.selection)
              .id(row.id)
              .onTapGesture { model.activate(i) }
          }
          if rows.isEmpty {
            Text(
              model.query.isEmpty
                ? "No tray apps found. Check Accessibility access." : "Nothing matches “\(model.query)”"
            )
            .foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.vertical, 24)
          }
        }
      }
      .scrollIndicators(.never)
      .onChange(of: model.selection) {
        if rows.indices.contains(model.selection) { proxy.scrollTo(rows[model.selection].id) }
      }
    }
  }

  private var footer: some View {
    HStack(spacing: 14) {
      ForEach(Array(model.hints.enumerated()), id: \.offset) { _, hint in
        HStack(spacing: 5) {
          ForEach(hint.keys, id: \.self) { KeyCap(text: $0) }
          Text(hint.label).font(.system(size: 13)).foregroundStyle(.secondary)
        }
      }
      Spacer()
    }
  }
}

private struct SettingsRowView: View {
  let row: SettingsModel.Row
  let selected: Bool

  var body: some View {
    HStack(spacing: 10) {
      if let item = row.item { AppIcon(item: item).frame(width: 22, height: 22) }
      Text(row.label).font(.system(size: 14)).lineLimit(1)
      Spacer(minLength: 12)
      switch row.kind {
      case .shortcut where !row.accent, .info where row.value.hasPrefix("⌘"):
        KeyCap(text: row.value)
      default:
        Text(row.value).font(.system(size: 14)).lineLimit(1)
          .foregroundStyle(row.accent ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
      }
    }
    .padding(.horizontal, 12)
    .frame(height: 36)
    .background(
      RoundedRectangle(cornerRadius: 10, style: .continuous).fill(selected ? Color.accentColor.opacity(0.16) : .clear)
    )
    .contentShape(Rectangle())
  }
}

/// About: icon, name, version, links (rows 0–2), Support Ukraine (row 3), credit (row 4) from `SettingsModel`.
private struct AboutCard: View {
  let model: SettingsModel

  var body: some View {
    let rows = model.rows
    VStack(spacing: 10) {
      Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 80, height: 80)
        .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
      Text("Trayfinder").font(.system(size: 24, weight: .bold))
      Text("Version \(model.version)").foregroundStyle(.secondary).textSelection(.enabled)
      Text("Find any menu bar item by name, and keep the ones you need in sight.")
        .font(.system(size: 14)).multilineTextAlignment(.center).frame(maxWidth: 380).padding(.top, 4)
      Text("Free and open source · MIT · update check only").font(.system(size: 12)).foregroundStyle(.secondary)
      HStack(spacing: 6) {
        ForEach(0..<min(3, rows.count), id: \.self) { i in link(rows[i], i) }
      }
      .padding(.top, 6)

      HStack(alignment: .top, spacing: 12) {
        VStack(spacing: 0) {
          Rectangle().fill(Color(red: 0, green: 0.357, blue: 0.733))
          Rectangle().fill(Color(red: 1, green: 0.835, blue: 0))
        }
        .frame(width: 26, height: 18).clipShape(RoundedRectangle(cornerRadius: 3)).accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 4) {
          Text("Support Ukraine").font(.system(size: 14, weight: .semibold))
          Text("Trayfinder is made by a Ukrainian developer. If it saves you time, please consider a donation.")
            .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
          HStack(spacing: 4) {
            if rows.count > 3 { link(rows[3], 3) }
          }
          .padding(.leading, -8)
        }
      }
      .padding(14)
      .frame(maxWidth: 420, alignment: .leading)
      .background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
      .padding(.top, 10)

      if rows.count > 4 {
        HStack(spacing: 0) {
          Text("Made by").font(.system(size: 12)).foregroundStyle(.secondary)
          link(rows[4], 4)
        }
        .padding(.top, 4)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private func link(_ row: SettingsModel.Row, _ i: Int) -> some View {
    Text(row.label)
      .font(.system(size: 14, weight: .semibold)).foregroundStyle(.tint)
      .padding(.horizontal, 8).padding(.vertical, 4)
      .background(
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .fill(i == model.selection ? Color.accentColor.opacity(0.16) : .clear)
      )
      .contentShape(Rectangle())
      .onTapGesture { model.activate(i) }
  }
}
