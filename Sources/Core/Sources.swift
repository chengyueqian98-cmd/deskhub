// 天气、邮件、日历、电量、量化的纯解析部分（请求和系统调用在 App/Fetch.swift）。
import Foundation

// —— 天气：Open-Meteo（免费、不用注册和 Key） ——
enum WeatherAPI {
  /** 没选城市时用上海（首次引导里会让用户自己选） */
  static let defaultCity: (name: String, lat: Double, lon: Double) = ("上海", 31.2304, 121.4737)

  /** WMO 天气代码 → 中文 + 图标名 */
  static func describe(_ code: Int, _ isDay: Int = 1) -> (text: String, icon: String) {
    let c = code
    if c == 0 { return ("晴", isDay != 0 ? "sun" : "moon") }
    if c <= 2 { return (c == 1 ? "晴间多云" : "多云", isDay != 0 ? "sun-cloud" : "moon-cloud") }
    if c == 3 { return ("阴", "cloud") }
    if c == 45 || c == 48 { return ("雾", "fog") }
    if c >= 51 && c <= 57 { return ("毛毛雨", "rain") }
    if c >= 61 && c <= 67 { return (c >= 65 ? "大雨" : c >= 63 ? "中雨" : "小雨", "rain") }
    if c >= 71 && c <= 77 { return (c >= 75 ? "大雪" : "小雪", "snow") }
    if c >= 80 && c <= 82 { return ("阵雨", "rain") }
    if c == 85 || c == 86 { return ("阵雪", "snow") }
    if c >= 95 { return ("雷雨", "storm") }
    return ("—", "cloud")
  }

  static func url(lat: Double, lon: Double) -> URL {
    var c = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
    c.queryItems = [
      .init(name: "latitude", value: jsNum(lat)), .init(name: "longitude", value: jsNum(lon)),
      .init(name: "timezone", value: "auto"), .init(name: "forecast_days", value: "5"),
      .init(name: "current", value: "temperature_2m,apparent_temperature,relative_humidity_2m,weather_code,is_day,wind_speed_10m"),
      .init(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max"),
    ]
    return c.url!
  }

  static func parse(_ d: JSON, city: String, now: Double = nowMs()) -> Weather? {
    guard let c = d["current"] as? JSON, let daily = d["daily"] as? JSON else { return nil }
    let r = { (v: Any?) in Int((num(v) ?? 0).rounded()) }
    let cur = describe(r(c["weather_code"]), r(c["is_day"]))
    let times = daily["time"] as? [String] ?? []
    func col(_ k: String) -> [Any] { daily[k] as? [Any] ?? [] }
    let days = times.indices.map { i -> WxDay in
      let dd = describe(r(col("weather_code")[safe: i]))
      return WxDay(date: times[i], max: r(col("temperature_2m_max")[safe: i]), min: r(col("temperature_2m_min")[safe: i]),
                   rain: num(col("precipitation_probability_max")[safe: i]).map { Int($0) }, text: dd.text, icon: dd.icon)
    }
    return Weather(city: city, at: now,
                   now: WxNow(temp: r(c["temperature_2m"]), feels: r(c["apparent_temperature"]), humidity: r(c["relative_humidity_2m"]), wind: r(c["wind_speed_10m"]), text: cur.text, icon: cur.icon),
                   days: days)
  }
}

extension Array {
  subscript(safe i: Int) -> Element? { i >= 0 && i < count ? self[i] : nil }
}

// —— 邮件：读 Mac「邮件」App 的未读邮件（AppleScript）。不发送、不删除、不标记已读 ——
enum MailAPI {
  static let US = "\u{1f}", RS = "\u{1e}"

  static func script(limit: Int = 12) -> String {
    """
    set US to (ASCII character 31)
    set RS to (ASCII character 30)
    tell application "Mail"
      set ms to (messages of inbox whose read status is false)
      set n to count of ms
      set out to (n as string)
      set lim to n
      if lim > \(limit) then set lim to \(limit)
      repeat with i from 1 to lim
        set m to item i of ms
        set d to date received of m
        set ds to ((year of d) as string) & "-" & ((month of d as integer) as string) & "-" & ((day of d) as string) & " " & ((time of d) as string)
        set acct to ""
        try
          set acct to name of account of mailbox of m
        end try
        set out to out & RS & (sender of m) & US & (subject of m) & US & ds & US & (message id of m) & US & acct
      end repeat
      return out
    end tell
    """
  }

  /** "张三 <a@b.com>" → (张三, a@b.com) */
  static func parseSender(_ s: String) -> (name: String, email: String) {
    if let m = s.match("^\\s*\"?([^\"<]*?)\"?\\s*<([^>]+)>\\s*$") {
      let name = (m[1] ?? "").trimmed()
      return (name.isEmpty ? m[2]! : name, m[2]!)
    }
    let t = s.trimmed()
    return (t, t)
  }

  /** osascript 的输出 → (未读总数, 最近几封) */
  static func parseOutput(_ text: String) -> (unread: Int, items: [MailItem]) {
    var t = text
    if t.hasSuffix("\n") { t.removeLast() }
    let parts = t.components(separatedBy: RS)
    let unread = Int(parts.first?.trimmed() ?? "") ?? 0
    let items = parts.dropFirst().map { row -> MailItem in
      let f = row.components(separatedBy: US)
      let g = { (i: Int) in i < f.count ? f[i] : "" }
      let who = parseSender(g(0))
      // time of d 是当天的秒数
      var ts: Double?
      if let dm = g(2).match("^(\\d+)-(\\d+)-(\\d+) (\\d+)$") {
        ts = localMs(Int(dm[1]!)!, Int(dm[2]!)!, Int(dm[3]!)!) + Double(Int(dm[4]!)!) * 1000
      }
      return MailItem(name: who.name, email: who.email, subject: g(1).isEmpty ? "（无主题）" : g(1), ts: ts, id: g(3), account: g(4))
    }.sorted { ($0.ts ?? 0) > ($1.ts ?? 0) }
    return (unread, items)
  }

  /** 读单封邮件的正文（只在你点开某一封、或让 AI 概括时才读；不标已读） */
  static let bodyScript = """
  on run argv
    set mid to item 1 of argv
    set lim to (item 2 of argv) as integer
    tell application "Mail"
      set ms to (messages of inbox whose read status is false and message id is mid)
      if (count of ms) is 0 then set ms to (messages of inbox whose message id is mid)
      if (count of ms) is 0 then return "NOTFOUND"
      set m to item 1 of ms
      set c to content of m
      if (length of c) > lim then set c to (text 1 thru lim of c)
      return (sender of m) & (ASCII character 31) & (subject of m) & (ASCII character 31) & c
    end tell
  end run
  """

  /** 正文脚本的输出 → (发件人, 邮箱, 主题, 正文)；找不到返回 nil */
  static func parseBody(_ text: String) -> (name: String, email: String, subject: String, body: String)? {
    var raw = text
    if raw.hasSuffix("\n") { raw.removeLast() }
    if raw == "NOTFOUND" { return nil }
    let f = raw.components(separatedBy: US)
    let who = parseSender(f.first ?? "")
    let body = f.dropFirst(2).joined(separator: US).replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
      .replace("[ \\t]+\n", "\n").replace("\n{3,}", "\n\n").trimmed()
    return (who.name, who.email, f.count > 1 && !f[1].isEmpty ? f[1] : "（无主题）", body)
  }

  /** 在「邮件」App 里打开这封邮件（和 JS 的 encodeURIComponent 一样转义） */
  static func messageUrl(_ id: String) -> String {
    var allowed = CharacterSet.alphanumerics.intersection(CharacterSet(charactersIn: Unicode.Scalar(0)..<Unicode.Scalar(128)))
    allowed.insert(charactersIn: "-_.!~*'()")
    return "message://%3c" + (id.addingPercentEncoding(withAllowedCharacters: allowed) ?? id) + "%3e"
  }
}

// —— 日历：月历要显示的范围 ——
enum CalendarRange {
  /** 本月 1 号所在那一周的周一，到再往后 6 周（月历一屏 6 行），至少覆盖今天起 7 天 */
  static func range(_ now: Double = nowMs()) -> (from: Double, to: Double) {
    let t = ymd(now)
    let first = ymd(localMs(t.y, t.m, 1))
    let fromDay = 1 - ((first.wd + 6) % 7)
    let from = localMs(t.y, t.m, fromDay)
    let to = localMs(t.y, t.m, fromDay + 42)
    let week = localMs(t.y, t.m, t.d + 8)
    return (from, max(to, week))
  }

  static let statusText: [Int: String] = [
    0: "还没授权读取日历", 1: "系统限制了日历访问",
    2: "你拒绝了日历权限，可以在「系统设置 → 隐私与安全性 → 日历」里打开",
    4: "只有写入权限，读不到日程，请在系统设置里改成“完全访问”",
  ]
}

// —— 电量 ——
enum BatteryInfo {
  /** "文略的AirPods Max 2" → "AirPods Max"：去掉「谁的」前缀和结尾的代次数字 */
  static func shortName(_ n: String) -> String {
    let s = n.replace("^.+?的", "").replace("\\s*\\d+$", "").trimmed()
    return s.isEmpty ? n : s
  }

  /** 配件类型：系统电源接口不给类型，按名字猜（不用 system_profiler，也不要蓝牙权限） */
  static func typeOf(_ name: String) -> String {
    let n = name.lowercased()
    if n.test("airpods|beats|headphone|headset|buds|耳机|wh-|wf-") { return "headphones" }
    if n.test("mouse|鼠标") { return "mouse" }
    if n.test("trackpad|触控板") { return "trackpad" }
    if n.test("keyboard|键盘") { return "keyboard" }
    if n.test("speaker|homepod|音箱") { return "speaker" }
    return "other"
  }

  /** pmset -g accps 的输出 → 设备（系统电源接口拿不到的蓝牙配件靠它补） */
  static func parsePmset(_ text: String) -> [BatteryDevice] {
    let ac = text.contains("'AC Power'")
    var out: [BatteryDevice] = []
    for line in text.components(separatedBy: "\n") {
      guard let m = line.match("^\\s*-(.*?)\\s*\\(id=\\d+\\)\\s*(\\d+)%;\\s*([^;]*)") else { continue }
      let raw = (m[1] ?? "").trimmed()
      let internalB = raw.hasPrefix("InternalBattery")
      let state = (m[3] ?? "").trimmed()
      out.append(BatteryDevice(
        name: internalB ? "Mac" : raw, pct: Int(m[2]!) ?? 0,
        // 「AC attached; not charging」= 接着电源但没在充（电池保护），不能算充电中
        charging: internalB ? (ac && state != "discharging" && state != "charged" && !line.contains("not charging")) : state == "charging",
        charged: state == "charged", internal: internalB, ac: internalB && ac,
        type: internalB ? "laptop" : typeOf(raw)))
    }
    return out
  }
}

// —— 量化系统：只读它写出来的文件，不改、不启动、不下单 ——
enum QuantAPI {
  /** 默认不接量化系统（大多数人没有）；在设置里选了文件夹才会去读 */
  static let defaultDir = ""

  /** 原系统是 Python 写的 JSON，里面可能有 NaN / Infinity（不是合法 JSON），先换成 null */
  static func readJSON(_ data: Data) -> JSON? {
    guard let s = String(data: data, encoding: .utf8) else { return nil }
    let fixed = s.replace("\\bNaN\\b|-?\\bInfinity\\b", "null")
    return (try? JSONSerialization.jsonObject(with: Data(fixed.utf8))) as? JSON
  }

  /** 把原系统的快照整理成要用的样子。修正原系统两个口径（只在显示上）：今日盈亏用 (现价-昨收)×股数，仓位用 市值/总资产 */
  static func summarize(_ state: JSON) -> QuantState {
    let acc = state["account"] as? JSON ?? [:]
    let positions = (state["positions"] as? [JSON] ?? []).map { p -> QuantPosition in
      let price = num(p["price"]), pct = num(p["pct_chg"]), shares = num(p["shares"])
      let prev = (pct != nil && price != nil) ? price! / (1 + pct! / 100) : nil
      let t = p["t_signal"] as? JSON
      return QuantPosition(
        code: str(p["code"]) ?? "", name: str(p["name"]) ?? "", shares: shares, cost: num(p["cost"]), price: price, pct: pct,
        mv: num(p["mv"]), pnl: num(p["pnl"]), pnlPct: num(p["pnl_pct"]),
        dayPnl: (prev != nil && shares != nil) ? round2((price! - prev!) * shares!) : nil,
        tType: str(t?["type"]) ?? "none", tMsg: str(t?["msg"]) ?? "",
        ma10: num(p["ma10"]), ma20: num(p["ma20"]), trend: str(p["trend"]) ?? "", signal: str(p["signal_today"]) ?? "",
        maxPrice: num(p["max_price"]), trailPct: num(p["trail_pct"]), kline: KLine.fromQuant(p["kline"] as? JSON))
    }
    let pick = { (w: JSON) in
      QuantPick(code: str(w["code"]) ?? "", name: str(w["name"]) ?? "", price: num(w["price"]), pct: num(w["pct_chg"]),
                ma10: num(w["ma10"]), ma20: num(w["ma20"]), trend: str(w["trend"]) ?? "", signal: str(w["signal_today"]) ?? "",
                strategy: str(w["strategy"]) ?? "", sector: str(w["sector_heat_name"]) ?? str(w["sector_name"]) ?? "", heat: str(w["sector_heat_label"]) ?? "",
                pe: num(w["pe"]), peg: num(w["peg"]), roe: num(w["roe"]), revGrow: num(w["rev_grow"]), profitGrow: num(w["profit_grow"]),
                mom60: num(w["mom60"]), bias20: num(w["bias20"]))
    }
    let total = num(acc["total_asset"]), initial = num(acc["initial_capital"]), mv = num(acc["market_value"])
    let r = state["risk"] as? JSON
    return QuantState(
      ok: true, running: nil, updatedAt: str(state["updated_at"]), positions: positions,
      risk: r.map { QuantRisk(status: str($0["status"]) ?? "", drawdown: num($0["cur_drawdown"]), halfLine: num($0["half_line"]), exitLine: num($0["exit_line"]), stopLoss: num($0["stop_loss_pct"]), peak: num($0["peak_asset"])) },
      account: QuantAccount(
        initial: initial, total: total,
        pnl: (total != nil && initial != nil && initial != 0) ? round2(total! - initial!) : nil,
        pnlPct: (total != nil && initial != nil && initial != 0) ? round2((total! - initial!) / initial! * 100) : nil,
        dayPnl: positions.reduce(0) { $0 + ($1.dayPnl ?? 0) },
        posRatio: (total != nil && total != 0 && mv != nil) ? round2(mv! / total! * 100, 1) : nil,
        cash: num(acc["cash"]), mv: mv),
      watchlist: (state["watchlist"] as? [JSON] ?? []).map(pick))
  }

  static func summarizeScan(_ sc: JSON?) -> QuantScan? {
    guard let sc else { return nil }
    let crit = sc["criteria"] as? JSON
    return QuantScan(
      at: str(sc["scanned_at"]) ?? "", mode: str(crit?["mode"]) ?? str(sc["scan_mode"]) ?? "", regime: str(sc["regime_label"]) ?? "",
      universe: num(sc["total_universe"]), prefiltered: num(sc["total_prefiltered"]), qualified: num(sc["total_qualified"]),
      candidates: (sc["candidates"] as? [JSON] ?? []).map { c in
        QuantPick(code: str(c["code"]) ?? "", name: str(c["name"]) ?? "", price: num(c["price"]), pct: num(c["pct_chg"]),
                  strategy: str(c["strategy"]) ?? "", sector: str(c["sector_heat_name"]) ?? str(c["sector_name"]) ?? "", heat: str(c["sector_heat_label"]) ?? "",
                  pe: num(c["pe"]), peg: num(c["peg"]), roe: num(c["roe"]), revGrow: num(c["rev_grow"]), profitGrow: num(c["profit_grow"]),
                  mom60: num(c["mom60"]), bias20: num(c["bias20"]))
      })
  }
}
