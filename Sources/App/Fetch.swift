// 各数据源的请求和系统调用。解析都在 Core 里（有测试），这里只负责「去拿」。
//
// 和 Electron 版相比省掉的东西：
//   · 日历：直接用 EventKit（以前每 5 分钟起一个 osascript 跑 JXA），日程变了系统会通知，不用轮询
//   · 繁→简：Foundation 自带转换（以前每次起 osascript）
//   · 电量：只在浮层打开时读（桌面层不显示电量），用 pmset，不再跑 system_profiler
import AppKit
import EventKit

enum Fetch {
  /** 不带缓存的会话：行情、新闻每次都要新的，缓存只会白占内存 */
  static let session: URLSession = {
    let c = URLSessionConfiguration.ephemeral
    c.urlCache = nil
    c.requestCachePolicy = .reloadIgnoringLocalCacheData
    c.timeoutIntervalForRequest = 10
    c.httpMaximumConnectionsPerHost = 4
    return URLSession(configuration: c)
  }()

  struct HTTPError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
  }

  static func get(_ url: URL, headers: [String: String] = [:], timeout: TimeInterval = 10) async throws -> Data {
    var req = URLRequest(url: url, timeoutInterval: timeout)
    for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
    let (data, resp) = try await session.data(for: req)
    if let h = resp as? HTTPURLResponse, !(200..<300).contains(h.statusCode) { throw HTTPError(message: "HTTP \(h.statusCode)") }
    return data
  }

  // —— 行情 ——
  static func quotes(_ keys: [String]) async throws -> [String: Quote] {
    guard !keys.isEmpty else { return [:] }
    let url = URL(string: "https://hq.sinajs.cn/list=" + keys.joined(separator: ","))!
    let data = try await get(url, headers: ["Referer": "https://finance.sina.com.cn"], timeout: 8)
    let gbk = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))
    let text = String(data: data, encoding: String.Encoding(rawValue: gbk)) ?? ""
    let raw = Market.splitResponse(text)
    var out: [String: Quote] = [:]
    for k in keys {
      do { out[k] = try Market.parseQuote(k, raw[k] ?? "") } catch {
        out[k] = Quote(key: k, code: Market.displayCode(k), market: Market.marketOf(k), failed: true, error: (error as? Market.ParseError)?.message ?? error.localizedDescription)
      }
    }
    return out
  }

  // —— 新闻 ——
  static func news(_ enabled: [String]) async throws -> NewsState {
    let sources = News.pick(enabled)
    let jobs = sources.flatMap { s in s.feeds.map { (s, $0) } }
    var lists: [[NewsItem]] = []
    var okCount = 0
    await withTaskGroup(of: [NewsItem]?.self) { g in
      for (s, f) in jobs {
        g.addTask {
          guard let url = URL(string: f.url),
                let d = try? await get(url, headers: ["User-Agent": "Mozilla/5.0 DeskHub"]),
                let xml = String(data: d, encoding: .utf8) ?? String(data: d, encoding: .isoLatin1) else { return nil }
          var items = Array(News.parseRss(xml, tag: f.tag, source: s.name).prefix(News.perFeed))
          if s.t2s { for i in items.indices { items[i].title = News.t2s(items[i].title); items[i].desc = News.t2s(items[i].desc) } }
          return items
        }
      }
      for await r in g { if let r { lists.append(r); okCount += 1 } }
    }
    if okCount == 0 { throw HTTPError(message: L("新闻源全部请求失败")) }
    return NewsState(items: Array(News.merge(lists).prefix(80)), at: nowMs())
  }

  // —— 天气 ——
  static func weather(_ city: (name: String, lat: Double, lon: Double)) async throws -> Weather {
    let d = try await get(WeatherAPI.url(lat: city.lat, lon: city.lon))
    guard let j = (try? JSONSerialization.jsonObject(with: d)) as? JSON, let w = WeatherAPI.parse(j, city: city.name) else {
      throw HTTPError(message: L("天气数据看不懂"))
    }
    return w
  }

  // —— 日历：EventKit（只读） ——
  static let eventStore = EKEventStore()

  static func calendarStatus() -> Int {
    switch EKEventStore.authorizationStatus(for: .event) {
    case .notDetermined: return 0
    case .restricted: return 1
    case .denied: return 2
    case .fullAccess: return 3
    case .writeOnly: return 4
    @unknown default: return 2
    }
  }

  static func calendar(apple: Bool = true, hidden: Set<String> = []) -> CalendarState {
    guard apple else { return CalendarState(ok: true, at: nowMs()) }
    let st = calendarStatus()
    guard st == 3 else { return CalendarState(ok: false, error: L(CalendarRange.statusText[st] ?? "没有日历权限"), needAuth: st == 0) }
    let r = CalendarRange.range()
    let cals = eventStore.calendars(for: .event).filter { !hidden.contains($0.calendarIdentifier) }
    if cals.isEmpty { return CalendarState(ok: true, at: nowMs()) }
    let pred = eventStore.predicateForEvents(withStart: Date(timeIntervalSince1970: r.from / 1000), end: Date(timeIntervalSince1970: r.to / 1000), calendars: cals)
    let evs = eventStore.events(matching: pred).prefix(400).map { e -> CalEvent in
      let c = e.calendar?.color?.usingColorSpace(.sRGB)
      return CalEvent(
        id: e.eventIdentifier ?? e.title ?? "", title: (e.title ?? "").isEmpty ? L("（无标题）") : e.title!,
        start: e.startDate.timeIntervalSince1970 * 1000, end: e.endDate.timeIntervalSince1970 * 1000,
        allDay: e.isAllDay, location: e.location ?? "", calendar: e.calendar?.title ?? "",
        color: c.map { [Int($0.redComponent * 255), Int($0.greenComponent * 255), Int($0.blueComponent * 255)] })
    }.sorted { $0.start < $1.start }
    return CalendarState(ok: true, events: evs, at: nowMs())
  }

  static func askCalendar() async -> CalendarState {
    _ = try? await eventStore.requestFullAccessToEvents()
    return calendar()
  }

  // —— 外部命令（邮件的 AppleScript、pmset） ——
  static func run(_ path: String, _ args: [String], timeout: TimeInterval = 30) async -> (code: Int32, out: String, err: String) {
    await withCheckedContinuation { cont in
      DispatchQueue.global(qos: .utility).async {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let o = Pipe(), e = Pipe()
        p.standardOutput = o
        p.standardError = e
        do { try p.run() } catch { cont.resume(returning: (-1, "", error.localizedDescription)); return }
        let killer = DispatchWorkItem { if p.isRunning { p.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)
        let out = o.fileHandleForReading.readDataToEndOfFile()
        let err = e.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        killer.cancel()
        cont.resume(returning: (p.terminationStatus, String(data: out, encoding: .utf8) ?? "", String(data: err, encoding: .utf8) ?? ""))
      }
    }
  }

  // —— 邮件：「邮件」没开就不去读（直接 tell 会把它启动起来，没登录账户时还会弹设置向导） ——
  static func mail() async -> MailState {
    let running = NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == "com.apple.mail" }
    guard running else { return MailState(ok: false, error: L("「邮件」App 没有打开"), notRunning: true) }
    let r = await run("/usr/bin/osascript", ["-e", MailAPI.script()], timeout: 60)
    if r.code != 0 {
      let msg = r.err.trimmed()
      if msg.test("-1743|not allowed|不允许") { return MailState(ok: false, error: L("没有控制「邮件」的权限，请在「系统设置 → 隐私与安全性 → 自动化」里允许")) }
      if msg.test("-1712|timed out|超时") { return MailState(ok: false, error: L("「邮件」App 响应超时")) }
      return MailState(ok: false, error: L("读取邮件失败：") + (msg.components(separatedBy: "\n").last ?? msg))
    }
    let p = MailAPI.parseOutput(r.out)
    return MailState(ok: true, unread: p.unread, items: p.items)
  }

  enum MailBody { case ok(name: String, email: String, subject: String, body: String), failed(String) }

  static func mailBody(_ id: String, maxChars: Int = 8000) async -> MailBody {
    guard NSWorkspace.shared.runningApplications.contains(where: { $0.bundleIdentifier == "com.apple.mail" }) else { return .failed(L("「邮件」App 没有打开")) }
    let r = await run("/usr/bin/osascript", ["-e", MailAPI.bodyScript, id, String(maxChars)], timeout: 60)
    if r.code != 0 {
      if r.err.test("-1743|not allowed|不允许") { return .failed(L("没有控制「邮件」的权限，请在「系统设置 → 隐私与安全性 → 自动化」里允许")) }
      return .failed(L("读取邮件失败：") + (r.err.trimmed().components(separatedBy: "\n").last ?? ""))
    }
    guard let b = MailAPI.parseBody(r.out) else { return .failed(L("在「邮件」里没找到这封邮件（可能已经被移走或删除）")) }
    return .ok(name: b.name, email: b.email, subject: b.subject, body: b.body)
  }

  /** 新浪日 K 线（A 股），详情里画图用 */
  static func daily(_ key: String, n: Int = 90) async -> KLine? {
    guard Market.marketOf(key) == "cn",
          let url = URL(string: "https://quotes.sina.cn/cn/api/json_v2.php/CN_MarketDataService.getKLineData?symbol=\(key)&scale=240&ma=no&datalen=\(n)"),
          let d = try? await get(url, headers: ["Referer": "https://finance.sina.com.cn"]),
          let rows = (try? JSONSerialization.jsonObject(with: d)) as? [JSON] else { return nil }
    return KLine.fromSina(rows)
  }

  /** 按城市名找经纬度（中文也行） */
  static func searchCity(_ name: String) async -> [(name: String, lat: Double, lon: Double, region: String)] {
    var c = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
    c.queryItems = [.init(name: "name", value: name), .init(name: "count", value: "6"), .init(name: "language", value: "zh")]
    guard let d = try? await get(c.url!), let j = (try? JSONSerialization.jsonObject(with: d)) as? JSON else { return [] }
    return (j["results"] as? [JSON] ?? []).compactMap { x in
      guard let lat = num(x["latitude"]), let lon = num(x["longitude"]) else { return nil }
      return (x["name"] as? String ?? "", lat, lon, [x["admin1"] as? String, x["country"] as? String].compactMap { $0 }.joined(separator: " · "))
    }
  }

  // —— 电量（Mac + 蓝牙配件）。左右耳机分开报的，合成一条取较低的那个 ——
  static func battery() async -> [BatteryDevice] {
    let r = await run("/usr/bin/pmset", ["-g", "accps"], timeout: 5)
    var merged: [BatteryDevice] = []
    for var d in BatteryInfo.parsePmset(r.out) {
      if d.name.isEmpty { d.name = L("耳机盒"); d.type = "headphones" }
      if let i = merged.firstIndex(where: { $0.name == d.name }) { merged[i].pct = min(merged[i].pct, d.pct); continue }
      merged.append(d)
    }
    return merged
  }

  // —— 量化系统 ——
  static func quant(_ dir: String) async -> QuantState {
    let path = dir + "/dashboard/state.json"
    guard let d = FileManager.default.contents(atPath: path) else { return QuantState(ok: false, error: L("没找到量化系统的数据文件：") + path) }
    guard let j = QuantAPI.readJSON(d) else { return QuantState(ok: false, error: L("读取失败：数据看不懂")) }
    var s = QuantAPI.summarize(j)
    s.dir = dir
    s.scan = FileManager.default.contents(atPath: dir + "/dashboard/scan_cache.json").flatMap(QuantAPI.readJSON).flatMap(QuantAPI.summarizeScan)
    let rep = dir + "/reports/daily"
    s.reports = ((try? FileManager.default.contentsOfDirectory(atPath: rep)) ?? [])
      .filter { $0.test("^\\d{4}-\\d{2}-\\d{2}\\.html$") }.sorted(by: >).prefix(20)
      .map { (String($0.prefix(10)), rep + "/" + $0) }
    // 原系统的看板服务是否在跑（/api/ping 不需要登录）
    s.running = (try? await get(URL(string: "http://127.0.0.1:8765/api/ping")!, timeout: 1.5)) != nil
    return s
  }
}
