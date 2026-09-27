import Carbon.HIToolbox

/// Global shortcuts through Carbon `RegisterEventHotKey`, which needs no Input Monitoring permission.
final class HotKeys {
  enum Action: UInt32, CaseIterable {
    case search = 1
  }

  private static let signature = OSType(0x5452_4644)  // 'TRFD'
  private static weak var current: HotKeys?

  private var refs: [Action: EventHotKeyRef] = [:]
  private var handlerRef: EventHandlerRef?
  private let onFire: (Action) -> Void

  init(onFire: @escaping (Action) -> Void) {
    self.onFire = onFire
    HotKeys.current = self
    var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
    InstallEventHandler(GetApplicationEventTarget(), hotKeyHandler, 1, &spec, nil, &handlerRef)
  }

  /// Replaces all registrations. A shortcut already taken by another app is skipped and logged.
  func register(_ bindings: [Action: Shortcut?]) {
    unregisterAll()
    for (action, shortcut) in bindings {
      guard let shortcut else { continue }
      var ref: EventHotKeyRef?
      let id = EventHotKeyID(signature: Self.signature, id: action.rawValue)
      let status = RegisterEventHotKey(
        shortcut.keyCode, shortcut.modifiers, id, GetApplicationEventTarget(), 0, &ref)
      if status == noErr, let ref {
        refs[action] = ref
      } else {
        Log.make("hotkeys").error("could not register \(shortcut.display, privacy: .public): \(status)")
      }
    }
  }

  func unregisterAll() {
    refs.values.forEach { UnregisterEventHotKey($0) }
    refs.removeAll()
  }

  fileprivate static func fire(_ id: UInt32) {
    guard let action = Action(rawValue: id) else { return }
    current?.onFire(action)
  }
}

nonisolated private func hotKeyHandler(_: EventHandlerCallRef?, _ event: EventRef?, _: UnsafeMutableRawPointer?)
  -> OSStatus
{
  var id = EventHotKeyID()
  GetEventParameter(
    event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
    MemoryLayout<EventHotKeyID>.size, nil, &id)
  // Carbon delivers hot keys on the main thread.
  MainActor.assumeIsolated { HotKeys.fire(id.id) }
  return noErr
}
