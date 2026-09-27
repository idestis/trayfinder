import AppKit
import Observation

/// State of the dropdown under the mark. Every key goes through `handle(_:)`.
/// Empty query: what's out of sight, most used first. Typing searches every item, pinned ones too.
@Observable
final class PaletteModel {
  var query = "" {
    didSet {
      selection = 0
      recompute()
    }
  }
  private(set) var results: [MenuBarItem] = []
  private(set) var section: Section = .mostUsed
  var selection = 0
  private(set) var toast: String?
  /// True while a favourite is being moved; the panel stays open even if it briefly loses key.
  private(set) var isPinning = false

  @ObservationIgnored let tray: TrayModel
  @ObservationIgnored var onClose: () -> Void = {}
  @ObservationIgnored var onSettings: () -> Void = {}
  @ObservationIgnored var onResultsChange: () -> Void = {}
  @ObservationIgnored private var toastTask: Task<Void, Never>?

  static let limit = 9

  enum Section: Equatable {
    case outOfSight(Int), mostUsed, matches(Int)
  }

  init(tray: TrayModel) { self.tray = tray }

  var selected: MenuBarItem? { results.indices.contains(selection) ? results[selection] : nil }
  var canPin: Bool { tray.trusted }

  func recompute() {
    let q = query.trimmingCharacters(in: .whitespaces)
    let hidden = tray.outOfSight
    let pool: [MenuBarItem]
    if !q.isEmpty {
      pool = tray.items
    } else if !hidden.isEmpty {
      pool = hidden
    } else {
      pool = tray.items
    }
    let ranked = Ranker.rank(pool, query: q, usage: tray.usage, favourites: Set(tray.favourites))
    section = !q.isEmpty ? .matches(ranked.count) : (!hidden.isEmpty ? .outOfSight(hidden.count) : .mostUsed)
    let next = Array(ranked.prefix(Self.limit))
    let countChanged = next.count != results.count
    results = next
    if selection >= results.count { selection = max(0, results.count - 1) }
    if countChanged { onResultsChange() }
  }

  func move(_ delta: Int) {
    guard !results.isEmpty else { return }
    selection = (selection + delta + results.count) % results.count
  }

  func open(_ index: Int) {
    guard results.indices.contains(index) else { return }
    let item = results[index]
    onClose()
    Task { await tray.open(item) }
  }

  func togglePin(_ index: Int? = nil) {
    let i = index ?? selection
    guard canPin, !isPinning, results.indices.contains(i) else { return }
    let item = results[i]
    selection = i
    let pin = !tray.isFavourite(item)
    isPinning = true
    Task {
      let ok = await tray.setFavourite(item, pin)
      isPinning = false
      recompute()
      if ok {
        show(
          pin
            ? String(localized: "\(item.title) now stays next to Trayfinder")
            : String(localized: "\(item.title) is no longer a favourite"))
      } else {
        show(String(localized: "Couldn't move \(item.title). Try ⌘-dragging it in the menu bar."))
      }
    }
  }

  /// ↵ on an empty list: ask for Accessibility, or restart once it's granted.
  func fixAccess() {
    if !tray.trusted {
      onClose()
      _ = AX.isTrusted(prompt: true)
      NSWorkspace.shared.open(Links.accessibilitySettings)
    } else if tray.needsRestart {
      Relaunch.now()
    }
  }

  private func show(_ message: String) {
    toast = message
    toastTask?.cancel()
    toastTask = Task {
      try? await Task.sleep(for: .seconds(2.5))
      if !Task.isCancelled { toast = nil }
    }
  }

  enum Key {
    case up, down, open, openIndex(Int), pin, settings, close
  }

  /// Returns true when the key was used.
  func handle(_ key: Key) -> Bool {
    switch key {
    case .up: move(-1)
    case .down: move(1)
    case .open:
      if results.isEmpty { fixAccess() } else { open(selection) }
    case .openIndex(let n): open(n)
    case .pin: togglePin()
    case .settings:
      onClose()
      onSettings()
    case .close: onClose()
    }
    return true
  }

  var footer: String {
    if let toast { return toast }
    if canPin { return String(localized: "⌘P keeps an icon next to Trayfinder, always in sight.") }
    return String(localized: "↵ opens · ⌘1–9 open a row · ⌘, settings")
  }
}
