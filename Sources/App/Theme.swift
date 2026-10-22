// 颜色和字体（和 Electron 版 widgets.css 的令牌一致）。
// 桌面层跟随系统浅/深色：深色 = 白字 + 黑雾，浅色 = 黑字 + 白雾；浮层是深色磨砂，一律用深色那组。
// 颜色整体降了一档饱和度：不用系统原色的荧光感。
import SwiftUI

struct Palette {
  let dark: Bool
  let text: Color, text2: Color, text3: Color
  let line: Color, fill: Color, fill2: Color
  var accent: Color, red: Color, green: Color, orange: Color
  let up: Color, down: Color
  var veil: Color, veil2: Color
  let glow: Color

  static func make(dark: Bool, theme: Theme? = nil) -> Palette {
    var p = base(dark: dark)
    if let theme {
      if let a = ACCENTS.first(where: { $0.id == theme.accent }) { p.accent = Color(hex: dark ? a.dark : a.light) }
      p.veil = p.veil.opacity(theme.veil); p.veil2 = p.veil2.opacity(theme.veil)
    }
    return p
  }

  private static func base(dark: Bool) -> Palette {
    dark
      ? Palette(dark: true,
                text: .white.opacity(0.92), text2: Color(r: 235, g: 235, b: 245, a: 0.62), text3: Color(r: 235, g: 235, b: 245, a: 0.38),
                line: .white.opacity(0.12), fill: .white.opacity(0.09), fill2: .white.opacity(0.15),
                accent: Color(hex: "#6a9fd8"), red: Color(hex: "#d9695f"), green: Color(hex: "#5aa882"), orange: Color(hex: "#d3a062"),
                up: Color(hex: "#c9625b"), down: Color(hex: "#50a07a"),
                veil: Color(r: 8, g: 10, b: 16, a: 0.55), veil2: Color(r: 8, g: 10, b: 16, a: 0.26),
                glow: .black.opacity(0.45))
      : Palette(dark: false,
                text: .black.opacity(0.88), text2: Color(r: 60, g: 60, b: 67, a: 0.72), text3: Color(r: 60, g: 60, b: 67, a: 0.46),
                line: Color(r: 60, g: 60, b: 67, a: 0.16), fill: Color(r: 120, g: 120, b: 128, a: 0.14), fill2: Color(r: 120, g: 120, b: 128, a: 0.22),
                accent: Color(hex: "#4a82c6"), red: Color(hex: "#cc5a50"), green: Color(hex: "#4a9a74"), orange: Color(hex: "#c28a45"),
                up: Color(hex: "#c9564f"), down: Color(hex: "#4a9a74"),
                veil: .white.opacity(0.62), veil2: .white.opacity(0.30),
                glow: .white.opacity(0.85))
  }

  /** 涨跌颜色：默认中性（▲ 亮 / ▼ 暗，不用红绿）；设置里可切红涨绿跌 / 绿涨红跌 */
  func change(_ v: Double?, colors: String) -> Color {
    guard let v, v != 0 else { return text3 }
    switch colors {
    case "rup": return v > 0 ? up : down
    case "gup": return v > 0 ? down : up
    default: return v > 0 ? text : text2
    }
  }
}

private struct PaletteKey: EnvironmentKey { static let defaultValue = Palette.make(dark: true) }
extension EnvironmentValues {
  var pal: Palette {
    get { self[PaletteKey.self] }
    set { self[PaletteKey.self] = newValue }
  }
}

extension Color {
  init(r: Double, g: Double, b: Double, a: Double = 1) { self.init(.sRGB, red: r / 255, green: g / 255, blue: b / 255, opacity: a) }
  init(hex: String) {
    let s = hex.replacingOccurrences(of: "#", with: "")
    let v = UInt32(s, radix: 16) ?? 0
    self.init(r: Double((v >> 16) & 0xff), g: Double((v >> 8) & 0xff), b: Double(v & 0xff))
  }
}

/** 字体：跟系统一致（拉丁和数字用 SF，中文自动落苹方）；数字用等宽，行情表对得齐 */
enum Font2 {
  static var scale = 1.0     // 主题里的字号：小 0.9 / 标准 1 / 大 1.15
  static func ui(_ size: CGFloat, _ w: Font.Weight = .regular) -> Font { .system(size: size * scale, weight: w) }
  static func num(_ size: CGFloat, _ w: Font.Weight = .regular) -> Font { .system(size: size * scale, weight: w).monospacedDigit() }
  static func round(_ size: CGFloat, _ w: Font.Weight = .semibold) -> Font { .system(size: size * scale, weight: w, design: .rounded).monospacedDigit() }
}

/** 主题里的强调色（深色 / 浅色各一份，都降过饱和度） */
let ACCENTS: [(id: String, name: String, dark: String, light: String)] = [
  ("blue", "雾蓝", "#6a9fd8", "#4a82c6"), ("purple", "淡紫", "#9a8cd8", "#7a6cc0"), ("green", "灰绿", "#5aa882", "#3f8f68"),
  ("orange", "琥珀", "#d3a062", "#b9833f"), ("pink", "藕粉", "#d38aa6", "#bb6a8a"), ("graphite", "石墨", "#a4a8b0", "#6e727a"),
]
