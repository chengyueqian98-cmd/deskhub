// 行情：新浪公开接口（免费、延迟数据）。只做展示和提醒，不做买卖、不给建议。
// 解析和交易时段判断是纯函数（从 Electron 版 market.js 移植）；请求在 App/Fetch.swift。
import Foundation

enum Market {
  /** 常用指数的别名，输入框里打中文也能加 */
  static let aliases: [String: String] = [
    "上证指数": "sh000001", "上证": "sh000001", "深证成指": "sz399001", "深证": "sz399001", "创业板指": "sz399006", "创业板": "sz399006",
    "沪深300": "sh000300", "科创50": "sh000688", "恒生指数": "rt_hkHSI", "恒指": "rt_hkHSI", "恒生科技": "rt_hkHSTECH",
    "标普500": "gb_inx", "标普": "gb_inx", "纳斯达克": "gb_ixic", "纳指": "gb_ixic", "道琼斯": "gb_dji", "道指": "gb_dji",
  ]

  /** 默认自选：几个大盘指数 + 几只大家都认识的（首次引导选「投资者」时用） */
  static let defaultWatch = ["sh000001", "sz399001", "rt_hkHSI", "gb_ixic", "gb_inx", "rt_hk00700", "gb_aapl", "gb_nvda"]

  /** 用户输入（代码、别名）→ 新浪代码；认不出返回 nil */
  static func toSinaKey(_ input: String) -> String? {
    let s = input.trimmed()
    if s.isEmpty { return nil }
    if let a = aliases[s] { return a }
    if s.test("^(sh|sz|bj)\\d{6}$", .caseInsensitive) { return s.lowercased() }
    if s.test("^rt_hk[0-9A-Z]+$") || s.test("^gb_[a-z$.]+$") { return s }
    if s.test("^\\d{6}$") {
      let c = s.first!
      if "695".contains(c) { return "sh" + s }
      if "0312".contains(c) { return "sz" + s }
      if "48".contains(c) { return "bj" + s }
      return nil
    }
    func hk(_ digits: String) -> String { "rt_hk" + String(repeating: "0", count: max(0, 5 - digits.count)) + digits }
    if s.test("^\\d{1,5}$") { return hk(s) }
    if s.test("^(hk)?\\d{1,5}(\\.hk)?$", .caseInsensitive) { return hk(s.replace("\\D", "")) }
    if s.test("^[A-Za-z][A-Za-z.]{0,9}$") {
      var low = s.lowercased()
      if let r = low.range(of: ".") { low.replaceSubrange(r, with: "$") }   // 和 JS 的 replace('.', '$') 一样只换第一个
      return "gb_" + low
    }
    return nil
  }

  /** 新浪代码属于哪个市场：cn / hk / us */
  static func marketOf(_ key: String) -> String {
    if key.test("^(sh|sz|bj)") { return "cn" }
    if key.hasPrefix("rt_hk") { return "hk" }
    return "us"
  }

  /** 显示用的代码：sz002185 → 002185，rt_hk00700 → 00700，gb_aapl → AAPL */
  static func displayCode(_ key: String) -> String {
    if key.test("^(sh|sz|bj)") { return String(key.dropFirst(2)) }
    if key.hasPrefix("rt_hk") { return String(key.dropFirst(5)) }
    return String(key.dropFirst(3)).replacingOccurrences(of: "$", with: ".").uppercased()
  }

  static func isIndex(_ key: String) -> Bool { key.test("^sh000|^sz399|^rt_hk[A-Z]|^gb_(inx|ixic|dji)$") }

  private static func n(_ x: String?) -> Double? {
    guard let x else { return nil }
    // parseFloat：取开头那段数字
    guard let m = x.trimmed().match("^[-+]?(\\d+\\.?\\d*|\\.\\d+)([eE][-+]?\\d+)?") else { return nil }
    return Double(m[0]!)
  }

  /** 北京时间字符串（2026-10-20 13:31:12 或 2026/10/20 13:31）→ 毫秒 */
  static func bjToMs(_ date: String?, _ time: String? = "00:00") -> Double? {
    guard let m = (date ?? "").match("(\\d{4})[/-](\\d{2})[/-](\\d{2})"),
          let t = (time ?? "").match("(\\d{2}):(\\d{2})(?::(\\d{2}))?") else { return nil }
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "UTC")!
    var c = DateComponents()
    c.year = Int(m[1]!); c.month = Int(m[2]!); c.day = Int(m[3]!)
    c.hour = Int(t[1]!)! - 8; c.minute = Int(t[2]!); c.second = Int(t[3] ?? "0") ?? 0
    return cal.date(from: c).map { $0.timeIntervalSince1970 * 1000 }
  }

  struct ParseError: Error { let message: String }

  /** 解析新浪一条返回（逗号分隔的字段），各市场字段位置不同 */
  static func parseQuote(_ key: String, _ raw: String) throws -> Quote {
    let f = raw.components(separatedBy: ",")
    func at(_ i: Int) -> String? { i < f.count ? f[i] : nil }
    let mk = marketOf(key)
    var q = Quote(key: key, code: displayCode(key), market: mk, index: isIndex(key))
    if mk == "cn" {
      // 名称,今开,昨收,现价,最高,最低,...,[30]日期,[31]时间
      q.name = at(0) ?? ""
      q.prev = n(at(2))
      q.price = n(at(3))
      if q.price == nil || q.price == 0 { q.price = q.prev }    // 开盘前、停牌时现价是 0
      q.open = n(at(1)); q.high = n(at(4)); q.low = n(at(5))
      q.ts = bjToMs(at(30), at(31))
    } else if mk == "hk" {
      // 英文名,中文名,今开,昨收,最高,最低,现价,...,[17]日期,[18]时间（指数和个股一样）
      q.name = (at(1).flatMap { $0.isEmpty ? nil : $0 }) ?? at(0) ?? ""
      q.price = n(at(6)); q.prev = n(at(3)); q.open = n(at(2)); q.high = n(at(4)); q.low = n(at(5))
      q.ts = bjToMs(at(17), at(18))
    } else {
      // 名称,现价,涨跌幅,时间（北京时间）,涨跌,今开,最高,最低,...
      q.name = at(0) ?? ""
      let price = n(at(1)), chg = n(at(4))
      q.price = price
      q.prev = (price != nil && chg != nil) ? round2(price! - chg!, 4) : nil
      q.open = n(at(5)); q.high = n(at(6)); q.low = n(at(7))
      let dt = (at(3) ?? "").components(separatedBy: " ")
      q.ts = bjToMs(dt.first, dt.count > 1 ? dt[1] : "00:00")
    }
    guard let price = q.price, price > 0, !q.name.isEmpty else { throw ParseError(message: "返回数据不完整") }
    if let prev = q.prev, prev != 0 {
      q.chg = round2(price - prev, 4)
      q.pct = round2((price - prev) / prev * 100)
    }
    if let pct = q.pct, abs(pct) > 50 { throw ParseError(message: "涨跌幅异常") }
    return q
  }

  /** 新浪返回的整段文字 → [key: 原始字段串] */
  static func splitResponse(_ text: String) -> [String: String] {
    var out: [String: String] = [:]
    for m in text.matchAll("hq_str_([\\w$]+)=\"([^\"]*)\"") { out[m[1]!] = m[2] ?? "" }
    return out
  }

  private static let sessions: [String: (tz: String, ranges: [(Int, Int)])] = [
    "cn": ("Asia/Shanghai", [(570, 690), (780, 900)]),
    "hk": ("Asia/Hong_Kong", [(570, 720), (780, 960)]),
    "us": ("America/New_York", [(570, 960)]),
  ]

  /** 市场此刻是否在交易时段（只看周末和时段，不含节假日） */
  static func isOpen(_ market: String, _ ms: Double = nowMs()) -> Bool {
    guard let s = sessions[market], let tz = TimeZone(identifier: s.tz) else { return false }
    let t = ymd(ms, tz)
    if t.wd == 0 || t.wd == 6 { return false }
    let mins = t.h * 60 + t.mi
    return s.ranges.contains { mins >= $0.0 && mins < $0.1 }
  }

  /** live 交易中 / closed 已收盘 / stale 数据过期 / fail 获取失败 */
  static func quoteStatus(_ q: Quote?, _ ms: Double = nowMs()) -> String {
    guard let q, !q.failed else { return "fail" }
    if !isOpen(q.market, ms) { return "closed" }
    if let ts = q.ts, ms - ts > 30 * 60 * 1000 { return "stale" }
    return "live"
  }

  /** 涨跌提醒：涨跌幅超过阈值、或价格穿过设定价时提醒。每种提醒每天只提醒一次（memo 记着） */
  static func checkAlerts(_ quotes: [Quote], pct: Double, prices: [String: Any], memo: inout Set<String>, day: String) -> [(title: String, body: String)] {
    var out: [(String, String)] = []
    func fire(_ id: String, _ title: String, _ body: String) {
      let k = "\(day)|\(id)"
      if !memo.contains(k) { memo.insert(k); out.append((title, body)) }
    }
    for q in quotes {
      guard !q.failed, let p = q.pct, let price = q.price else { continue }
      let name = "\(q.name)（\(q.code)）"
      if pct > 0 && abs(p) >= pct {
        fire("\(q.key)|pct\(p > 0 ? "+" : "-")", L(p > 0 ? "%@ 涨幅 %@%%" : "%@ 跌幅 %@%%", name, String(format: "%.2f", abs(p))), L("现价 %@，超过你设的 %@%% 提醒线", jsNum(price), jsNum(pct)))
      }
      let rule = prices[q.key] as? JSON
      if let above = num(rule?["above"]), above != 0, price >= above { fire("\(q.key)|above\(jsNum(above))", L("%@ 升到 %@", name, jsNum(price)), L("已到达你设的 %@", jsNum(above))) }
      if let below = num(rule?["below"]), below != 0, price <= below { fire("\(q.key)|below\(jsNum(below))", L("%@ 跌到 %@", name, jsNum(price)), L("已到达你设的 %@", jsNum(below))) }
    }
    return out
  }
}
