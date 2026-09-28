import SwiftUI

extension View {
  /// Liquid Glass on macOS 26 and later, a translucent material before that.
  @ViewBuilder
  func glassPanel(radius: CGFloat) -> some View {
    let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
    if #available(macOS 26.0, *) {
      self.glassEffect(.regular, in: shape)
    } else {
      self.background(.regularMaterial, in: shape)
        .overlay(shape.strokeBorder(.white.opacity(0.18)))
    }
  }
}

/// Transparent room around a panel for its SwiftUI shadow. The window server's own shadow follows the
/// square window bounds and shows as a grey frame around rounded glass, so panels turn it off.
/// The margin must hold the whole blur (about twice the radius) plus the offset, or the window clips it.
enum PanelShadow {
  static let margin: CGFloat = 56
}

extension View {
  /// A tight contact shadow for the edge and a wide, faint one for lift, like a system menu.
  func panelShadow() -> some View {
    self
      .shadow(color: .black.opacity(0.10), radius: 1, y: 0.5)
      .shadow(color: .black.opacity(0.14), radius: 20, y: 10)
      .padding(PanelShadow.margin)
  }
}

/// A small key cap, for hints and shortcut values.
struct KeyCap: View {
  let text: String
  var body: some View {
    Text(text)
      .font(.system(size: 12, weight: .medium, design: .rounded))
      .padding(.horizontal, 7).padding(.vertical, 2)
      .background(.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
      .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(.primary.opacity(0.12)))
  }
}
