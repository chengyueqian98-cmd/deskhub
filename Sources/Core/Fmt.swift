// 格式化（纯函数）：从 Electron 版 src/desk/lib/fmt.js 移植，输出的文字一模一样。
import Foundation

enum F {
  private static var fmts: [Int: NumberFormatter] = [:]
  private static func fmt(_ d: Int) -> NumberFormatter {
    if let f = fmts[d] { return f }
    let f = NumberFormatter()
    f.locale = Locale(identifier: "en_US")
    f.numberStyle = .decimal
    f.minimumFractionDigits = d
    f.maximumFractionDigits = d
    f.roundingMode = .halfUp
    fmts[d] = f
    return f
  }

  /** 千分位 + 固定小数位 */
  static func num(_ v: Double?, _ d: Int = 2) -> String {
    guard let v, v.isFinite else { return "—" }
    return fmt(d).string(from: NSNumber(value: v)) ?? "—"
  }

  /** 价格：1 以下多留一位小数 */
  static func price(_ v: Double?) -> String {
    guard let v else { return "—" }
    return num(v, abs(v) >= 1 ? 2 : 3)
  }

  static func pct(_ v: Double?, _ d: Int = 2) -> String {
    guard let v, v.isFinite else { return "—" }
    return (v > 0 ? "+" : "") + String(format: "%.\(d)f", v) + "%"
  }

  /** 中性表示（不用红绿）：▲ 0.12% / ▼ 1.32%。方向靠箭头，强弱靠亮度 */
  static func pctMono(_ v: Double?, _ d: Int = 2) -> String {
    guard let v, v.isFinite else { return "—" }
    if v == 0 { return String(format: "%.\(d)f", 0.0) + "%" }
    return (v > 0 ? "▲ " : "▼ ") + String(format: "%.\(d)f", abs(v)) + "%"
  }

  static func signed(_ v: Double?, _ d: Int = 2) -> String {
    guard let v, v.isFinite else { return "—" }
    return (v > 0 ? "+" : "") + num(v, d)
  }

  static func money(_ v: Double?, _ d: Int = 2) -> String { v == nil ? "—" : "¥" + num(v, d) }

  /** up / down / flat */
  static func cls(_ v: Double?) -> String {
    guard let v, v != 0 else { return "flat" }
    return v > 0 ? "up" : "down"
  }

  static func hm(_ ms: Double) -> String { let t = ymd(ms); return "\(pad2(t.h)):\(pad2(t.mi))" }

  static var week: [String] { appLang == "en" ? ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"] : ["周日", "周一", "周二", "周三", "周四", "周五", "周六"] }
  static var weekHeads: [String] { appLang == "en" ? ["M", "T", "W", "T", "F", "S", "S"] : ["一", "二", "三", "四", "五", "六", "日"] }
  private static let months = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
  static func monthName(_ m: Int) -> String { appLang == "en" ? months[(m - 1) % 12] : "\(m)月" }
  /** 周四 10月22日 / Thu, Oct 22 */
  static func dateShort(_ ms: Double) -> String {
    let t = ymd(ms)
    return appLang == "en" ? "\(week[t.wd]), \(months[t.m - 1].prefix(3)) \(t.d)" : "\(week[t.wd]) \(t.m)月\(t.d)日"
  }

  private static func sameDay(_ a: YMD, _ b: YMD) -> Bool { a.y == b.y && a.m == b.m && a.d == b.d }
  private static func shift(_ ms: Double, days: Int) -> YMD {
    let t = ymd(ms)
    return ymd(localMs(t.y, t.m, t.d + days, t.h, t.mi))
  }

  /** 今天 / 明天 / 昨天 / 周三 10月22日 */
  static func dayLabel(_ ms: Double, _ now: Double = nowMs()) -> String {
    let d = ymd(ms), n = ymd(now)
    if sameDay(d, n) { return L("今天") }
    if sameDay(d, shift(now, days: 1)) { return L("明天") }
    if sameDay(d, shift(now, days: -1)) { return L("昨天") }
    return dateShort(ms)
  }

  /** 刚刚 / 5 分钟前 / 今天 13:20 / 昨天 09:10 / 10-18 09:10 */
  static func rel(_ ms: Double?, _ now: Double = nowMs()) -> String {
    guard let ms, ms != 0 else { return "—" }
    let diff = now - ms
    if diff < 60e3 && diff > -60e3 { return L("刚刚") }
    if diff > 0 && diff < 3600e3 { return appLang == "en" ? "\(Int(diff / 60e3)) min ago" : "\(Int(diff / 60e3)) 分钟前" }
    let d = ymd(ms), n = ymd(now)
    if sameDay(d, n) { return L("今天") + " " + hm(ms) }
    if sameDay(d, shift(now, days: -1)) { return L("昨天") + " " + hm(ms) }
    return "\(pad2(d.m))-\(pad2(d.d)) \(hm(ms))"
  }

  /** 某个时区的时:分 */
  static func zoneTime(_ tz: String, _ now: Double = nowMs()) -> String {
    guard let z = TimeZone(identifier: tz) else { return "—" }
    let t = ymd(now, z)
    return "\(pad2(t.h)):\(pad2(t.mi))"
  }

  static func zoneWeekday(_ tz: String, _ now: Double = nowMs()) -> String {
    guard let z = TimeZone(identifier: tz) else { return "" }
    return week[ymd(now, z).wd]
  }

  static func statusText(_ status: String, _ market: String) -> String {
    switch status {
    case "live": return L(["cn": "交易中", "hk": "交易中·延迟约15分钟", "us": "交易中·延迟报价"][market] ?? "交易中")
    case "closed": return L("已收盘")
    case "stale": return L("数据过期")
    case "fail": return L("获取失败")
    default: return "—"
    }
  }

  /** 发件人名字 → 头像上的字（中文取最后一个字，英文取首字母） */
  static func initials(_ name: String) -> String {
    let s = name.replace("[\"'<>]", "").trimmed()
    if s.isEmpty { return "?" }
    if s.test("[一-龥]") {
      let han = s.replace("[^一-龥]", "")
      return han.isEmpty ? String(s.prefix(1)) : String(han.suffix(1))
    }
    let words = s.split(whereSeparator: { $0.isWhitespace })
    return String(words.compactMap(\.first).map(String.init).joined().prefix(2)).uppercased()
  }

  /** 发件人头像的底色：按名字取一个柔和的颜色，同一个人永远同一种 */
  static let avatarColors = ["#c99a5b", "#6fa88a", "#6b8fbf", "#9a80b3", "#c0736d", "#6aa5ae", "#b87a92", "#8e8e93"]
  static func avatarBg(_ name: String) -> String {
    var h: UInt32 = 0
    for ch in name.unicodeScalars { h = h &* 31 &+ ch.value }
    return avatarColors[Int(h % UInt32(avatarColors.count))]
  }

  static func riskText(_ status: String?) -> String {
    switch status {
    case "normal": return L("正常")
    case "half": return L("降半仓警戒")
    case "exit": return L("清仓警戒")
    default: return status ?? "—"
    }
  }

  /** 本地日期 → "2026-10-20" */
  static func dayKey(_ ms: Double) -> String { let t = ymd(ms); return "\(t.y)-\(pad2(t.m))-\(pad2(t.d))" }

  /** 月历的 42 格（6 行 × 7 列，周一开头）。month 从 1 开始 */
  static func monthCells(_ year: Int, _ month: Int) -> [(ms: Double, inMonth: Bool, day: Int, weekend: Bool)] {
    let first = ymd(localMs(year, month, 1))
    let startDay = 1 - ((first.wd + 6) % 7)
    return (0..<42).map { i in
      let t = ymd(localMs(year, month, startDay + i, 12))
      return (localMs(t.y, t.m, t.d), t.m == month, t.d, t.wd == 0 || t.wd == 6)
    }
  }

  /** 快捷键的显示：Control+Alt+Space → ⌃⌥空格 */
  static func hotkeyLabel(_ acc: String?) -> String {
    let parts = (acc ?? "Control+Alt+Space").split(separator: "+").map(String.init)
    return parts.map { p -> String in
      switch p.lowercased() {
      case "control", "ctrl": return "⌃"
      case "alt", "option": return "⌥"
      case "shift": return "⇧"
      case "command", "cmd", "commandorcontrol", "cmdorctrl", "super", "meta": return "⌘"
      case "space": return L("空格")
      default: return p.uppercased()
      }
    }.joined()
  }
}
