import Carbon.HIToolbox
import Foundation
import Testing

struct ShortcutTests {
  @Test func displayOrderIsMacStandard() {
    let s = Shortcut(keyCode: UInt32(kVK_Space), modifiers: UInt32(cmdKey | shiftKey | optionKey | controlKey))
    #expect(s.display == "⌃⌥⇧⌘Space")
  }

  @Test func needsARealModifier() {
    #expect(!Shortcut(keyCode: UInt32(kVK_ANSI_A), modifiers: 0).isValid)
    #expect(!Shortcut(keyCode: UInt32(kVK_ANSI_A), modifiers: UInt32(shiftKey)).isValid)
    #expect(Shortcut.defaultSearch.isValid)
  }

  @Test func convertsCocoaFlags() {
    let cocoa: UInt = (1 << 20) | (1 << 19)  // command + option
    #expect(Shortcut.carbonModifiers(cocoa: cocoa) == UInt32(cmdKey | optionKey))
  }
}

@MainActor
struct PreferencesTests {
  private func defaults() -> UserDefaults { UserDefaults(suiteName: "tests.\(UUID().uuidString)")! }

  @Test func defaultsAreSensible() {
    let p = Preferences(defaults: defaults())
    #expect(p.searchShortcut == .defaultSearch)
    #expect(p.vimKeys)
    #expect(!p.centered)
  }

  @Test func clearedShortcutStaysCleared() {
    let d = defaults()
    let p = Preferences(defaults: d)
    p.searchShortcut = nil
    #expect(Preferences(defaults: d).searchShortcut == nil)
  }

  @Test func shortcutRoundTrips() {
    let d = defaults()
    let custom = Shortcut(keyCode: UInt32(kVK_ANSI_K), modifiers: UInt32(cmdKey | optionKey))
    Preferences(defaults: d).searchShortcut = custom
    #expect(Preferences(defaults: d).searchShortcut == custom)
  }
}

struct DefaultShortcutTests {
  @Test func defaultsAvoidBrowserAndInputMethodKeys() {
    #expect(Shortcut.defaultSearch.display == "⌃⌥T")
  }
}
