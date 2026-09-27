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
enum PanelShadow {
  static let margin: CGFloat = 28
}

extension View {
  func panelShadow() -> some View {
    self.shadow(color: .black.opacity(0.22), radius: 18, y: 8).padding(PanelShadow.margin)
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
