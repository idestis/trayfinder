import SwiftUI

/// The dropdown under the mark: filter field, a section of rows, a one-line footer.
struct PaletteView: View {
  @Bindable var model: PaletteModel
  var focusToken: Int
  @FocusState private var focused: Bool

  // Fixed metrics, so the controller can size the panel before SwiftUI lays it out.
  static let width: CGFloat = 400
  static let rowHeight: CGFloat = 50
  static let rowSpacing: CGFloat = 2
  private static let pad: CGFloat = 10
  private static let fieldHeight: CGFloat = 40
  private static let headerHeight: CGFloat = 30
  private static let footerHeight: CGFloat = 44

  static func height(rows: Int) -> CGFloat {
    let n = CGFloat(max(rows, 1))
    let list = n * rowHeight + (n - 1) * rowSpacing
    return pad + fieldHeight + 6 + headerHeight + list + footerHeight + pad
  }

  var body: some View {
    VStack(spacing: 0) {
      field
      Spacer().frame(height: 6)
      header
      VStack(spacing: Self.rowSpacing) {
        ForEach(Array(model.results.enumerated()), id: \.element.id) { idx, item in
          ResultRow(
            item: item, index: idx, selected: idx == model.selection,
            pinned: model.tray.isFavourite(item), canPin: model.canPin,
            onOpen: { model.open(idx) }, onPin: { model.togglePin(idx) })
        }
        if model.results.isEmpty { empty }
      }
      Text(model.footer)
        .font(.system(size: 12)).foregroundStyle(.secondary)
        .lineLimit(2)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .frame(height: Self.footerHeight)
    }
    .padding(Self.pad)
    .frame(width: Self.width, height: Self.height(rows: model.results.count), alignment: .top)
    .glassPanel(radius: 20)
    .panelShadow()
    .onChange(of: focusToken) { focusSoon() }
    .onAppear { focusSoon() }
  }

  /// A freshly hosted view in a non-activating panel isn't ready for focus on the first pass.
  private func focusSoon() { DispatchQueue.main.async { focused = true } }

  private var field: some View {
    HStack(spacing: 10) {
      Image(systemName: "magnifyingglass").font(.system(size: 14, weight: .medium)).foregroundStyle(.secondary)
      TextField(placeholder, text: $model.query)
        .textFieldStyle(.plain)
        .font(.system(size: 15))
        .focused($focused)
    }
    .padding(.horizontal, 12)
    .frame(height: Self.fieldHeight)
    .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
  }

  private var placeholder: String {
    model.canPin
      ? String(localized: "Type to find any menu bar icon")
      : String(localized: "Search menu bar")
  }

  private var header: some View {
    HStack {
      Text(sectionTitle).font(.system(size: 11, weight: .semibold)).textCase(.uppercase).kerning(0.4)
      Spacer()
      Text("Most used first").font(.system(size: 11))
    }
    .foregroundStyle(.secondary)
    .padding(.horizontal, 10)
    .frame(height: Self.headerHeight)
  }

  private var sectionTitle: String {
    switch model.section {
    case .outOfSight(let n): String(localized: "Out of sight · \(n)")
    case .mostUsed: String(localized: "Everything is in sight")
    case .matches(let n): String(localized: "Matches · \(n)")
    }
  }

  @ViewBuilder private var empty: some View {
    Group {
      if !model.tray.trusted {
        Text("Accessibility access required. Press ↵ to allow it.")
      } else if model.tray.needsRestart {
        Text("Access granted. Press ↵ to restart Trayfinder.")
      } else {
        Text("Nothing matches “\(model.query)”")
      }
    }
    .font(.system(size: 13)).foregroundStyle(.secondary).multilineTextAlignment(.center)
    .frame(maxWidth: .infinity).frame(height: Self.rowHeight)
    .contentShape(Rectangle())
    .onTapGesture { model.fixAccess() }
  }
}

private struct ResultRow: View {
  let item: MenuBarItem
  let index: Int
  let selected: Bool
  let pinned: Bool
  let canPin: Bool
  let onOpen: () -> Void
  let onPin: () -> Void

  var body: some View {
    HStack(spacing: 12) {
      AppIcon(item: item).frame(width: 28, height: 28)
      VStack(alignment: .leading, spacing: 1) {
        Text(item.title).font(.system(size: 14, weight: .semibold)).lineLimit(1)
        if let subtitle = item.subtitle {
          Text(subtitle).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
        }
      }
      Spacer(minLength: 8)
      if index < PaletteModel.limit {
        Text("⌘\(index + 1)").font(.system(size: 12, design: .rounded)).foregroundStyle(.secondary)
      }
      if canPin {
        Button(action: onPin) {
          Image(systemName: pinned ? "pin.fill" : "pin")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(pinned ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            .frame(width: 26, height: 26)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(pinned ? "Favourite: stays next to Trayfinder" : "Make it a favourite")
        .accessibilityLabel(pinned ? "Remove \(item.title) from favourites" : "Make \(item.title) a favourite")
      }
    }
    .padding(.horizontal, 10)
    .frame(height: PaletteView.rowHeight)
    .background(
      RoundedRectangle(cornerRadius: 11, style: .continuous)
        .fill(selected ? Color.primary.opacity(0.1) : .clear)
    )
    .contentShape(Rectangle())
    .onTapGesture(perform: onOpen)
  }
}

/// The app's icon; a symbol for Apple's agents; a letter tile for apps that ship no icon.
struct AppIcon: View {
  let item: MenuBarItem

  private static var cache: [pid_t: NSImage?] = [:]

  var body: some View {
    GeometryReader { geo in
      let side = geo.size.width
      if let symbol = SystemItems.symbol(item.bundleID) {
        tile(side) { Image(systemName: symbol).font(.system(size: side * 0.5, weight: .medium)) }
      } else if let image = Self.icon(item.pid) {
        Image(nsImage: image).resizable().interpolation(.high)
      } else {
        tile(side) { Text(item.title.prefix(1).uppercased()).font(.system(size: side * 0.5, weight: .bold)) }
      }
    }
    .aspectRatio(1, contentMode: .fit)
  }

  private func tile(_ side: CGFloat, @ViewBuilder _ content: () -> some View) -> some View {
    RoundedRectangle(cornerRadius: side * 0.24, style: .continuous)
      .fill(.background.opacity(0.8))
      .overlay(RoundedRectangle(cornerRadius: side * 0.24, style: .continuous).strokeBorder(.primary.opacity(0.12)))
      .overlay(content().foregroundStyle(.primary))
      .frame(width: side, height: side)
  }

  /// nil when the app bundle declares no icon (the system would show a generic executable).
  private static func icon(_ pid: pid_t) -> NSImage? {
    if let hit = cache[pid] { return hit }
    let app = NSRunningApplication(processIdentifier: pid)
    let info = app?.bundleURL.flatMap { Bundle(url: $0)?.infoDictionary }
    let hasIcon = info?["CFBundleIconFile"] != nil || info?["CFBundleIconName"] != nil
    let image = hasIcon ? app?.icon : nil
    if cache.count > 64 { cache.removeAll() }
    cache[pid] = image
    return image
  }
}
