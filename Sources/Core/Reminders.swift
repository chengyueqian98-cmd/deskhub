// AI 提醒（从 Electron 版 reminders.js 移植）：到点后在后台让 AI 跑一段话，结果发系统通知、贴在提醒卡上。
// 没写 AI 指令的提醒就是普通闹钟式提醒。存在 desk.json 的 reminders 里，格式和旧版一样：
// { id, title, time:'08:00', days:[1..7]（周一=1，空=每天）, prompt, context:{calendar,mail,market,quant},
//   enabled, lastRunDay, lastResult, lastRunAt, lastError }
import Foundation

enum Reminders {
  static func new(title: String = "", time: String = "08:00", days: [Int] = [], prompt: String = "",
                  context: [String: Bool] = ["calendar": true, "mail": true, "market": false, "quant": false], enabled: Bool = true) -> JSON {
    [
      "id": "r" + String(Int(Date().timeIntervalSince1970 * 1000), radix: 36) + String(UUID().uuidString.prefix(4)).lowercased(),
      "title": title, "time": time, "days": days, "prompt": prompt, "context": context,
      "enabled": enabled, "lastRunDay": NSNull(), "lastResult": NSNull(), "lastRunAt": NSNull(), "lastError": NSNull(),
    ]
  }

  /** 本地日期 → 2026-10-20（和旧版一样补零） */
  static func dayKey(_ ms: Double) -> String { F.dayKey(ms) }

  private static func isoWeekday(_ ms: Double) -> Int { let w = ymd(ms).wd; return w == 0 ? 7 : w }
  private static func minutes(_ time: Any?) -> Int? {
    let p = ((time as? String) ?? "").components(separatedBy: ":").compactMap { Int($0) }
    return p.count == 2 ? p[0] * 60 + p[1] : nil
  }
  static func days(_ r: JSON) -> [Int] { (r["days"] as? [Any] ?? []).compactMap { num($0).map { Int($0) } } }

  /** 现在该跑哪些：到了时间、今天还没跑过、今天是选中的星期几。错过 2 小时以上的不补跑 */
  static func due(_ list: [JSON], now: Double = nowMs()) -> [JSON] {
    let today = dayKey(now)
    let t = ymd(now)
    let mins = t.h * 60 + t.mi
    return list.filter { r in
      guard (r["enabled"] as? Bool) == true, (r["lastRunDay"] as? String) != today else { return false }
      let d = days(r)
      if !d.isEmpty && !d.contains(isoWeekday(now)) { return false }
      guard let at = minutes(r["time"]) else { return false }
      return mins >= at && mins - at <= 120
    }
  }

  /** 下次什么时候提醒（给界面显示） */
  static func nextRun(_ r: JSON, now: Double = nowMs()) -> Double? {
    guard (r["enabled"] as? Bool) == true, let at = minutes(r["time"]) else { return nil }
    let t = ymd(now)
    for i in 0..<8 {
      let d = localMs(t.y, t.m, t.d + i, at / 60, at % 60)
      if d <= now || (i == 0 && (r["lastRunDay"] as? String) == dayKey(now)) { continue }
      let ds = days(r)
      if !ds.isEmpty && !ds.contains(isoWeekday(d)) { continue }
      return d
    }
    return nil
  }

  /** 拼给 AI 的话：用户的指令 + 选中的桌面数据。规定不给买卖建议 */
  static func buildPrompt(_ r: JSON, calendar: String?, mail: String?, market: String?, quant: String?, now: Double = nowMs()) -> String {
    let t = ymd(now)
    var parts = [
      "你是用户 Mac 桌面上的提醒助手。现在是 \(t.y)/\(t.m)/\(t.d) \(pad2(t.h)):\(pad2(t.mi))。",
      "请用简体中文、简短地回答（适合放进系统通知和桌面小卡片，200 字以内，可以分几行）。",
      "如果涉及股票行情，只做客观描述，不要给出任何买入、卖出或持有的建议。",
      "不需要使用任何工具，直接根据下面的信息回答。",
      "",
      "用户的要求：\(r["prompt"] as? String ?? "")",
    ]
    if let calendar { parts += ["", "【日程】", calendar] }
    if let mail { parts += ["", "【未读邮件（只有发件人和主题）】", mail] }
    if let market { parts += ["", "【自选行情（延迟数据）】", market] }
    if let quant { parts += ["", "【量化系统快照】", quant] }
    return parts.joined(separator: "\n")
  }

  /** 通知里只放得下前一两行 */
  static func notifyBody(_ text: String) -> String {
    String(text.replace("[#*`>]", "").replace("\\n{2,}", "\n").trimmed().prefix(180))
  }

  /** 模板（提醒页「从模板开始」） */
  static let templates: [(title: String, time: String, days: [Int], prompt: String, context: [String: Bool])] = [
    ("早间简报", "08:00", [], "总结今天的日程和值得先看的未读邮件，提醒我最重要的一两件事。", ["calendar": true, "mail": true, "market": false, "quant": false]),
    ("A 股开盘", "21:25", [1, 2, 3, 4, 5], "用三四句话客观描述一下我自选里各市场现在的情况。", ["calendar": false, "mail": false, "market": true, "quant": true]),
    ("收工复盘", "22:30", [1, 2, 3, 4, 5], "看看明天有什么日程需要提前准备，列成清单。", ["calendar": true, "mail": true, "market": false, "quant": false]),
    ("喝水休息", "15:00", [], "", [:]),
  ]
}
