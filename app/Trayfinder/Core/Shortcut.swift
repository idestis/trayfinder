import Carbon.HIToolbox
import Foundation

/// A global key combination, stored with Carbon key code and modifier flags.
nonisolated struct Shortcut: Codable, Equatable, Hashable, Sendable {
  var keyCode: UInt32
  var modifiers: UInt32

  // ⌃⌥T ("T" for Trayfinder). Not ⌘⇧T: browsers use it to reopen closed tabs; ⌥Space clashes with input methods.
  static let defaultSearch = Shortcut(keyCode: UInt32(kVK_ANSI_T), modifiers: UInt32(controlKey | optionKey))

  /// A global shortcut needs at least one of ⌃ ⌥ ⌘, or it would swallow normal typing.
  var isValid: Bool { modifiers & UInt32(cmdKey | optionKey | controlKey) != 0 }

  var display: String {
    var s = ""
    if modifiers & UInt32(controlKey) != 0 { s += "⌃" }
    if modifiers & UInt32(optionKey) != 0 { s += "⌥" }
    if modifiers & UInt32(shiftKey) != 0 { s += "⇧" }
    if modifiers & UInt32(cmdKey) != 0 { s += "⌘" }
    return s + Self.keyName(keyCode)
  }

  /// Carbon modifier flags from Cocoa ones (NSEvent.ModifierFlags raw values).
  static func carbonModifiers(cocoa flags: UInt) -> UInt32 {
    var m: UInt32 = 0
    if flags & (1 << 18) != 0 { m |= UInt32(controlKey) }
    if flags & (1 << 19) != 0 { m |= UInt32(optionKey) }
    if flags & (1 << 17) != 0 { m |= UInt32(shiftKey) }
    if flags & (1 << 20) != 0 { m |= UInt32(cmdKey) }
    return m
  }

  static func keyName(_ code: UInt32) -> String {
    if let special = specialKeys[Int(code)] { return special }
    return layoutCharacter(code)?.uppercased() ?? "#\(code)"
  }

  private static let specialKeys: [Int: String] = [
    kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
    kVK_Escape: "⎋", kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
    kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
    kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
    kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
  ]

  /// The character this key types on the current keyboard layout, ignoring modifiers.
  private static func layoutCharacter(_ code: UInt32) -> String? {
    guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
      let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
    else { return nil }
    let data = Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue() as Data
    return data.withUnsafeBytes { buf -> String? in
      guard let layout = buf.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return nil }
      var dead: UInt32 = 0
      var chars = [UniChar](repeating: 0, count: 4)
      var len = 0
      let status = UCKeyTranslate(
        layout, UInt16(code), UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
        OptionBits(kUCKeyTranslateNoDeadKeysBit), &dead, chars.count, &len, &chars)
      guard status == noErr, len > 0 else { return nil }
      return String(utf16CodeUnits: chars, count: len)
    }
  }
}
