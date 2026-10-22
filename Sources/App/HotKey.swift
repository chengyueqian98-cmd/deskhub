// 全局快捷键（Carbon 的 RegisterEventHotKey：不需要「辅助功能」权限）。
// 默认 ⌃⌥空格。不用 ⌥空格：macOS 15 起只带 ⌥ 的全局快捷键注册「成功」但按了不触发，按键会落到访达。
import AppKit
import Carbon.HIToolbox

final class HotKey {
  private var ref: EventHotKeyRef?
  private var handler: EventHandlerRef?
  private let action: () -> Void
  private(set) var registered = false

  init(action: @escaping () -> Void) {
    self.action = action
    var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
    let me = Unmanaged.passUnretained(self).toOpaque()
    InstallEventHandler(GetApplicationEventTarget(), { _, _, data in
      guard let data else { return noErr }
      let hk = Unmanaged<HotKey>.fromOpaque(data).takeUnretainedValue()
      DispatchQueue.main.async { hk.action() }
      return noErr
    }, 1, &spec, me, &handler)
  }

  /** "Control+Alt+Space" 这种写法（和 Electron 版设置里存的一样）→ 注册；返回是否成功 */
  @discardableResult
  func register(_ accelerator: String) -> Bool {
    unregister()
    guard let (code, mods) = HotKey.parse(accelerator) else { return false }
    let id = EventHotKeyID(signature: OSType(0x4453_4b48), id: 1)   // 'DSKH'
    let st = RegisterEventHotKey(code, mods, id, GetApplicationEventTarget(), 0, &ref)
    registered = st == noErr
    return registered
  }

  func unregister() {
    if let ref { UnregisterEventHotKey(ref) }
    ref = nil
    registered = false
  }

  static func parse(_ acc: String) -> (UInt32, UInt32)? {
    var mods: UInt32 = 0
    var code: UInt32?
    for p in acc.split(separator: "+").map({ $0.lowercased() }) {
      switch p {
      case "control", "ctrl": mods |= UInt32(controlKey)
      case "alt", "option": mods |= UInt32(optionKey)
      case "shift": mods |= UInt32(shiftKey)
      case "command", "cmd", "commandorcontrol", "cmdorctrl", "super", "meta": mods |= UInt32(cmdKey)
      case "space": code = UInt32(kVK_Space)
      case "return", "enter": code = UInt32(kVK_Return)
      default:
        if let c = keyCodes[p] { code = c }
      }
    }
    guard let code, mods != 0 else { return nil }
    return (code, mods)
  }

  private static let keyCodes: [String: UInt32] = [
    "a": UInt32(kVK_ANSI_A), "b": UInt32(kVK_ANSI_B), "c": UInt32(kVK_ANSI_C), "d": UInt32(kVK_ANSI_D), "e": UInt32(kVK_ANSI_E),
    "f": UInt32(kVK_ANSI_F), "g": UInt32(kVK_ANSI_G), "h": UInt32(kVK_ANSI_H), "i": UInt32(kVK_ANSI_I), "j": UInt32(kVK_ANSI_J),
    "k": UInt32(kVK_ANSI_K), "l": UInt32(kVK_ANSI_L), "m": UInt32(kVK_ANSI_M), "n": UInt32(kVK_ANSI_N), "o": UInt32(kVK_ANSI_O),
    "p": UInt32(kVK_ANSI_P), "q": UInt32(kVK_ANSI_Q), "r": UInt32(kVK_ANSI_R), "s": UInt32(kVK_ANSI_S), "t": UInt32(kVK_ANSI_T),
    "u": UInt32(kVK_ANSI_U), "v": UInt32(kVK_ANSI_V), "w": UInt32(kVK_ANSI_W), "x": UInt32(kVK_ANSI_X), "y": UInt32(kVK_ANSI_Y),
    "z": UInt32(kVK_ANSI_Z), "0": UInt32(kVK_ANSI_0), "1": UInt32(kVK_ANSI_1), "2": UInt32(kVK_ANSI_2), "3": UInt32(kVK_ANSI_3),
    "4": UInt32(kVK_ANSI_4), "5": UInt32(kVK_ANSI_5), "6": UInt32(kVK_ANSI_6), "7": UInt32(kVK_ANSI_7), "8": UInt32(kVK_ANSI_8),
    "9": UInt32(kVK_ANSI_9), "`": UInt32(kVK_ANSI_Grave),
  ]
}
