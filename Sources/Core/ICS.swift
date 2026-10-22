// 日历订阅链接（iCalendar / .ics）：Google 日历的「iCal 格式的私密地址」、Outlook 的发布链接、学校课表都能用。
// 支持：全天 / 带时区 / UTC 时间、多行折叠、转义；重复规则 RRULE 的 DAILY / WEEKLY（含 BYDAY）/ MONTHLY / YEARLY、
// INTERVAL / COUNT / UNTIL、EXDATE（删掉的那几次）、RECURRENCE-ID（单独改过的那一次）。
import Foundation

enum ICS {
  struct VEvent {
    var uid = "", summary = "", location = ""
    var start: Double = 0, end: Double = 0, allDay = false
    var tz: TimeZone = .current
    var rrule: [String: String] = [:]
    var exdates: Set<Double> = []
    var recurrenceId: Double?
  }

  /** 折叠行展开（下一行以空格或 Tab 开头 = 接着上一行） */
  static func unfold(_ text: String) -> [String] {
    var out: [String] = []
    for line in text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n") {
      if (line.hasPrefix(" ") || line.hasPrefix("\t")), !out.isEmpty { out[out.count - 1] += line.dropFirst() } else { out.append(line) }
    }
    return out
  }

  static func unescape(_ s: String) -> String {
    s.replacingOccurrences(of: "\\n", with: " ").replacingOccurrences(of: "\\N", with: " ")
      .replacingOccurrences(of: "\\,", with: ",").replacingOccurrences(of: "\\;", with: ";").replacingOccurrences(of: "\\\\", with: "\\")
  }

  /** 20261020T090000Z / 20261020T090000（配 TZID 或本地）/ 20261020（全天）→ (毫秒, 是否全天) */
  static func date(_ v: String, tzid: String?) -> (ms: Double, allDay: Bool)? {
    let s = v.trimmed()
    guard let m = s.match("^(\\d{4})(\\d{2})(\\d{2})(?:T(\\d{2})(\\d{2})(\\d{2})?(Z)?)?$") else { return nil }
    var c = DateComponents()
    c.year = Int(m[1]!); c.month = Int(m[2]!); c.day = Int(m[3]!)
    let allDay = m[4] == nil
    c.hour = Int(m[4] ?? "0"); c.minute = Int(m[5] ?? "0"); c.second = Int(m[6] ?? "0")
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = m[7] != nil ? TimeZone(identifier: "UTC")! : (tzid.flatMap { TimeZone(identifier: $0) } ?? .current)
    if allDay { cal.timeZone = .current }
    return cal.date(from: c).map { ($0.timeIntervalSince1970 * 1000, allDay) }
  }

  /** 一行 → (名字, 参数, 值)。DTSTART;TZID=Asia/Shanghai:20261020T090000 */
  static func field(_ line: String) -> (name: String, params: [String: String], value: String)? {
    guard let colon = line.firstIndex(of: ":") else { return nil }
    let head = line[..<colon], value = String(line[line.index(after: colon)...])
    let parts = head.components(separatedBy: ";")
    var params: [String: String] = [:]
    for p in parts.dropFirst() { let kv = p.components(separatedBy: "="); if kv.count == 2 { params[kv[0].uppercased()] = kv[1].replacingOccurrences(of: "\"", with: "") } }
    return (parts[0].uppercased(), params, value)
  }

  static func events(_ text: String) -> [VEvent] {
    var out: [VEvent] = []
    var cur: VEvent?
    var duration: Double?
    for line in unfold(text) {
      if line.hasPrefix("BEGIN:VEVENT") { cur = VEvent(); duration = nil; continue }
      if line.hasPrefix("END:VEVENT") {
        if var e = cur {
          if e.end == 0 { e.end = e.start + (duration ?? (e.allDay ? 86400e3 : 3600e3)) }
          out.append(e)
        }
        cur = nil
        continue
      }
      guard cur != nil, let f = field(line) else { continue }
      switch f.name {
      case "UID": cur!.uid = f.value
      case "SUMMARY": cur!.summary = unescape(f.value)
      case "LOCATION": cur!.location = unescape(f.value)
      case "DTSTART":
        if let d = date(f.value, tzid: f.params["TZID"]) { cur!.start = d.ms; cur!.allDay = d.allDay }
        if let t = f.params["TZID"], let z = TimeZone(identifier: t) { cur!.tz = z }
      case "DTEND": if let d = date(f.value, tzid: f.params["TZID"]) { cur!.end = d.ms }
      case "DURATION": duration = parseDuration(f.value)
      case "RRULE":
        for kv in f.value.components(separatedBy: ";") { let p = kv.components(separatedBy: "="); if p.count == 2 { cur!.rrule[p[0].uppercased()] = p[1] } }
      case "EXDATE":
        for v in f.value.components(separatedBy: ",") { if let d = date(v, tzid: f.params["TZID"]) { cur!.exdates.insert(d.ms) } }
      case "RECURRENCE-ID": cur!.recurrenceId = date(f.value, tzid: f.params["TZID"])?.ms
      default: break
      }
    }
    return out
  }

  /** PT1H30M / P1D → 毫秒 */
  static func parseDuration(_ s: String) -> Double? {
    guard let m = s.match("^-?P(?:(\\d+)W)?(?:(\\d+)D)?(?:T(?:(\\d+)H)?(?:(\\d+)M)?(?:(\\d+)S)?)?$") else { return nil }
    let n = { (i: Int) in Double(m[i] ?? "0") ?? 0 }
    return ((n(1) * 7 + n(2)) * 86400 + n(3) * 3600 + n(4) * 60 + n(5)) * 1000
  }

  private static let weekdays = ["SU": 1, "MO": 2, "TU": 3, "WE": 4, "TH": 5, "FR": 6, "SA": 7]

  /** 把重复的日程在 [from, to) 里展开成一次一次的 */
  static func expand(_ e: VEvent, from: Double, to: Double, limit: Int = 500) -> [Double] {
    let len = e.end - e.start
    guard let freq = e.rrule["FREQ"] else { return e.start + len > from && e.start < to ? [e.start] : [] }
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = e.allDay ? .current : e.tz
    cal.firstWeekday = 2
    let interval = max(1, Int(e.rrule["INTERVAL"] ?? "1") ?? 1)
    let count = Int(e.rrule["COUNT"] ?? "")
    let until = e.rrule["UNTIL"].flatMap { date($0, tzid: nil)?.ms }.map { $0 + (e.rrule["UNTIL"]!.count == 8 ? 86400e3 - 1 : 0) }
    let byday = (e.rrule["BYDAY"] ?? "").components(separatedBy: ",").compactMap { weekdays[String($0.suffix(2))] }
    let start = Date(timeIntervalSince1970: e.start / 1000)
    var out: [Double] = []
    var produced = 0
    let unit: Calendar.Component = ["DAILY": .day, "WEEKLY": .weekOfYear, "MONTHLY": .month, "YEARLY": .year][freq] ?? .day
    var step = 0
    while step < 3000 && produced < limit {
      guard let base = cal.date(byAdding: unit, value: step * interval, to: start) else { break }
      var dates: [Date] = [base]
      if freq == "WEEKLY" && !byday.isEmpty {
        // 这一周（周一开头）里，BYDAY 列出的那几天，时间和第一次一样
        let weekStart = cal.dateInterval(of: .weekOfYear, for: base)!.start
        let hms = cal.dateComponents([.hour, .minute, .second], from: start)
        dates = (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: weekStart) }
          .filter { byday.contains(cal.component(.weekday, from: $0)) }
          .compactMap { cal.date(bySettingHour: hms.hour ?? 0, minute: hms.minute ?? 0, second: hms.second ?? 0, of: $0) }
          .filter { $0 >= start }
      }
      var done = false
      for d in dates {
        let ms = d.timeIntervalSince1970 * 1000
        if let until, ms > until { done = true; break }
        if let count, produced >= count { done = true; break }
        produced += 1
        if ms >= to { done = true; break }
        if ms + len > from && !e.exdates.contains(ms) { out.append(ms) }
      }
      if done { break }
      step += 1
    }
    return out
  }

  /** 整份 .ics → 范围里的日程（单独改过的那一次替换掉原来那次） */
  static func parse(_ text: String, from: Double, to: Double, calendar: String, color: [Int]? = nil) -> [CalEvent] {
    let all = events(text)
    let overrides = all.filter { $0.recurrenceId != nil }
    var replaced: [String: Set<Double>] = [:]
    for o in overrides { replaced[o.uid, default: []].insert(o.recurrenceId!) }
    var out: [CalEvent] = []
    for e in all where e.recurrenceId == nil && e.start > 0 {
      for s in expand(e, from: from, to: to) where !(replaced[e.uid]?.contains(s) ?? false) {
        out.append(CalEvent(id: "\(e.uid)@\(Int(s))", title: e.summary.isEmpty ? L("（无标题）") : e.summary, start: s, end: s + (e.end - e.start),
                            allDay: e.allDay, location: e.location, calendar: calendar, color: color))
      }
    }
    for o in overrides where o.start + (o.end - o.start) > from && o.start < to {
      out.append(CalEvent(id: "\(o.uid)@\(Int(o.start))", title: o.summary, start: o.start, end: o.end, allDay: o.allDay, location: o.location, calendar: calendar, color: color))
    }
    return out.sorted { $0.start < $1.start }
  }

  /** webcal:// 开头的订阅链接换成 https:// */
  static func url(_ s: String) -> URL? {
    let t = s.trimmed()
    return URL(string: t.lowercased().hasPrefix("webcal://") ? "https://" + t.dropFirst(9) : t)
  }
}

// —— 农历和节日（Foundation 自带农历历法） ——
enum Lunar {
  private static let months = ["正", "二", "三", "四", "五", "六", "七", "八", "九", "十", "冬", "腊"]
  private static let tens = ["初", "十", "廿", "三"]
  private static let digits = ["", "一", "二", "三", "四", "五", "六", "七", "八", "九", "十"]

  static func parts(_ ms: Double) -> (month: Int, day: Int, leap: Bool) {
    var cal = Calendar(identifier: .chinese)
    cal.timeZone = TimeZone(identifier: "Asia/Shanghai")!
    // 按「你这里的今天」算农历：把本地的年月日放到上海的中午再换算（否则美国的白天在上海已经是第二天）
    let t = ymd(ms)
    var g = Calendar(identifier: .gregorian)
    g.timeZone = cal.timeZone
    let noon = g.date(from: DateComponents(year: t.y, month: t.m, day: t.d, hour: 12)) ?? Date(timeIntervalSince1970: ms / 1000)
    let c = cal.dateComponents([.month, .day], from: noon)
    return (c.month ?? 1, c.day ?? 1, c.isLeapMonth ?? false)
  }

  /** 九月初二 / 闰六月十五 */
  static func text(_ ms: Double) -> String {
    let p = parts(ms)
    if appLang == "en" { return "Lunar \(p.leap ? "leap " : "")\(p.month)/\(p.day)" }
    let d = p.day
    let day: String = d == 10 ? "初十" : d == 20 ? "二十" : d == 30 ? "三十" : tens[d / 10] + digits[d % 10]
    return (p.leap ? "闰" : "") + months[p.month - 1] + "月" + day
  }

  static let lunarFestivals: [(m: Int, d: Int, name: String)] = [(1, 1, "春节"), (1, 15, "元宵节"), (5, 5, "端午节"), (7, 7, "七夕"), (8, 15, "中秋节"), (9, 9, "重阳节"), (12, 8, "腊八")]
  static let solarFestivals: [(m: Int, d: Int, name: String)] = [(1, 1, "元旦"), (2, 14, "情人节"), (5, 1, "劳动节"), (6, 1, "儿童节"), (10, 1, "国庆节"), (12, 25, "圣诞节")]

  /** 清明（21 世纪的经验公式，误差不超过一天） */
  static func qingming(_ year: Int) -> Int { Int(Double(year % 100) * 0.2422 + 4.81) - (year % 100) / 4 }

  /** 某一天是什么节日（没有就 nil）。除夕 = 春节前一天 */
  static func festival(_ ms: Double) -> String? {
    let t = ymd(ms)
    if let f = solarFestivals.first(where: { $0.m == t.m && $0.d == t.d }) { return f.name }
    if t.m == 4 && t.d == qingming(t.y) { return "清明" }
    let p = parts(ms)
    if !p.leap, let f = lunarFestivals.first(where: { $0.m == p.month && $0.d == p.day }) { return f.name }
    let tomorrow = parts(localMs(t.y, t.m, t.d + 1, 12))
    if tomorrow.month == 1 && tomorrow.day == 1 && !tomorrow.leap { return "除夕" }
    return nil
  }

  /** 从今天起最近的节日：(名字, 还有几天)，今天就是返回 0 */
  static func next(_ now: Double = nowMs(), within: Int = 400) -> (name: String, days: Int)? {
    let t = ymd(now)
    for i in 0..<within {
      let ms = localMs(t.y, t.m, t.d + i, 12)
      if let f = festival(ms) { return (f, i) }
    }
    return nil
  }
}

// —— 汇率（open.er-api.com，免费、不用注册，每天更新） ——
enum FX {
  static func url(_ base: String) -> URL { URL(string: "https://open.er-api.com/v6/latest/\(base.uppercased())")! }
  static func parse(_ j: JSON) -> (rates: [String: Double], updated: Double)? {
    guard j["result"] as? String == "success", let r = j["rates"] as? JSON else { return nil }
    var rates: [String: Double] = [:]
    for (k, v) in r { if let n = num(v) { rates[k] = n } }
    return (rates, (num(j["time_last_update_unix"]) ?? 0) * 1000)
  }
  static let names = ["USD": "美元", "CNY": "人民币", "HKD": "港币", "EUR": "欧元", "GBP": "英镑", "JPY": "日元", "KRW": "韩元", "CAD": "加元", "AUD": "澳元", "SGD": "新加坡元", "TWD": "新台币", "CHF": "瑞士法郎"]
}
