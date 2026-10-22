// 数据中心：定时拉行情、新闻、天气、量化、日历、邮件，算管家，推给桌面层和浮层（两个窗口共用这一份，不各算一套）。
// 锁屏、睡眠时暂停请求，回来时马上刷新一次。
import AppKit
import EventKit
import UserNotifications

@MainActor
final class DeskModel: ObservableObject {
  let store: Store

  @Published var quotes: [String: Quote] = [:]
  @Published var marketError: String?
  @Published var marketAt: Double = 0
  @Published var news: NewsState?
  @Published var weather: Weather?
  @Published var calendar: CalendarState?
  @Published var mail: MailState?
  @Published var battery: [BatteryDevice] = []
  @Published var quant: QuantState?
  @Published var layout: Layout
  @Published var butler = ButlerDay()
  @Published var storeRev = 0           // 设置变了：读 store 的视图跟着重画
  @Published var editing = false        // 浮层里的「编辑小组件」
  @Published var page = "home"          // 浮层页面：home / butler
  @Published var overlayVisible = false
  @Published var toast: String?           // 浮层底部一行小提示（几秒后自己消失）
  @Published var overlayChat: Chat        // 浮层底部那条 AI 输入的对话
  @Published var mailOpen: String?        // 浮层里正在看正文的那封邮件
  @Published var symbolOpen: String?      // 市场页正在看详情的品种
  var runningReminders = Set<String>()
  // —— 新组件的数据（按组件 id 分开存：同一种可以加好几个，各看各的） ——
  @Published var crypto: [String: [CoinQuote]] = [:]
  var icsEvents: [CalEvent] = []
  @Published var sys = SysStat()
  @Published var fx: [String: (rates: [String: Double], updated: Double)] = [:]
  @Published var nowPlaying: NowPlaying?
  let sampler = SysSampler()                        // 订阅链接里的日程
  @Published var repos: [String: [RepoInfo]] = [:]
  @Published var feeds: [String: NewsState] = [:]
  @Published var todos: TodoState?
  @Published var cityWeather: [String: Weather] = [:]     // 天气组件各自设的城市
  @Published var photos: [String: String] = [:]           // 照片组件当前显示的那张
  @Published var pomo = Pomodoro()
  @Published var layouts: [String: Layout] = [:]          // 其它显示器的布局（主屏的是 layout）
  @Published var configOpen: String?                      // 浮层里正在设置的组件
  @Published var update: Update.Release?               // GitHub 上有比现在新的版本
  @Published var updateStatus = ""                     // 设置页里「检查更新」的结果
  var overlayKey = "main"                                 // 浮层开在哪块屏上（编辑的就是那块屏的布局）
  var aiImportant = Set<String>(), aiAsked = Set<String>()
  var onKeys: ((Set<String>) -> Void)?   // 设置变了要窗口层配合的（快捷键、刘海）

  private var tasks: [String: Task<Void, Never>] = [:]
  private var paused = false
  private var alertMemo = Set<String>()
  private var butlerTimer: Task<Void, Never>?
  private var quantWatch: DispatchSourceFileSystemObject?

  init(store: Store) {
    self.store = store
    // 老用户（有布局、没走过引导）：直接当已经引导过，原来的设置一样不动
    if !store.onboarded && store.data["layout"] != nil { store.set(["onboarded": true, "lang": "zh"]) }
    appLang = store.lang
    layout = normalize(store.layout)
    overlayChat = Chat(agent: store.data["aiAgent"] as? String == "claude" ? "claude" : "deepseek")
    for (k, v) in store.data["screenLayouts"] as? JSON ?? [:] { layouts[k] = normalize(v) }
    store.onChange = { [weak self] keys in
      guard let self else { return }
      self.storeRev &+= 1
      if keys.contains("layout") { let L = normalize(self.store.layout); if L != self.layout { self.layout = L } }
      if keys.contains("lang") { appLang = self.store.lang }
      if keys.contains("widgetConfig") { self.kickWidgets() }
      if keys.contains("theme") { Font2.scale = self.theme.scale }
      if keys.contains("watch") { self.kick("market") }
      if keys.contains("city") { self.kick("weather") }
      if keys.contains("newsSources") { self.kick("news") }
      if keys.contains("quantDir") { self.watchQuant() }
      if keys.contains("mail") { self.kick("mail") }
      if keys.contains("calendarSettings") { self.kick("ics"); self.refreshCalendar() }
      self.onKeys?(keys)
    }
  }

  // —— 循环 ——
  func start() {
    loop("market", every: { [unowned self] in self.anyOpen() ? 5 : 60 }) { await $0.refreshMarket() }
    loop("news", every: { 15 * 60 }) { await $0.refreshNews() }
    loop("weather", every: { 15 * 60 }) { await $0.refreshWeather() }
    loop("quant", every: { 60 }) { await $0.refreshQuant() }
    loop("calendar", every: { 30 * 60 }) { $0.refreshCalendar() }
    loop("ics", every: { 30 * 60 }) { await $0.refreshICS() }   // 日程变了系统会发通知（见下），这里只是兜底
    if !measuring { loop("mail", every: { 2 * 60 }) { await $0.refreshMail() } }
    loop("reminders", every: { 30 }) { $0.checkReminders() }
    loop("crypto", every: { 120 }) { await $0.refreshCrypto() }
    loop("github", every: { 30 * 60 }) { await $0.refreshRepos() }
    loop("feeds", every: { 15 * 60 }) { await $0.refreshFeeds() }
    loop("cities", every: { 15 * 60 }) { await $0.refreshCities() }
    loop("todos", every: { 10 * 60 }) { $0.refreshTodos() }
    loop("photos", every: { 30 * 60 }) { $0.rotatePhotos() }
    loop("update", every: { 6 * 3600 }) { await $0.checkUpdate() }
    // 系统状态：只有组件开着才采样（桌面上 5 秒一次，浮层开着 2 秒一次）
    loop("sys", every: { [unowned self] in self.instances("sysstat").isEmpty ? 60 : (self.overlayVisible ? 2 : 5) }) { m in
      if !m.instances("sysstat").isEmpty { m.sys = m.sampler.sample() }
    }
    loop("fx", every: { 6 * 3600 }) { await $0.refreshFX() }
    for (name, app) in [("com.apple.Music.playerInfo", "Music"), ("com.spotify.client.PlaybackStateChanged", "Spotify")] {
      DistributedNotificationCenter.default().addObserver(forName: .init(name), object: nil, queue: .main) { [weak self] n in
        let info = n.userInfo ?? [:]
        MainActor.assumeIsolated { self?.playerChanged(app: app, info: info) }
      }
    }
    Font2.scale = theme.scale
    NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: Fetch.eventStore, queue: .main) { [weak self] _ in
      MainActor.assumeIsolated { self?.refreshCalendar(); self?.refreshTodos() }
    }
    watchQuant()
  }

  private func loop(_ name: String, every: @escaping () -> TimeInterval, _ fn: @escaping (DeskModel) async -> Void) {
    loops[name] = (every, fn)
    restart(name)
  }
  private var loops: [String: (() -> TimeInterval, (DeskModel) async -> Void)] = [:]

  private func restart(_ name: String) {
    guard let (every, fn) = loops[name] else { return }
    tasks[name]?.cancel()
    tasks[name] = Task { [weak self] in
      while !Task.isCancelled {
        guard let self else { return }
        if !self.paused { await fn(self) }
        try? await Task.sleep(nanoseconds: UInt64(every() * 1e9))
      }
    }
  }

  /** 立刻跑一次某个循环（并重新计时） */
  func kick(_ name: String) { restart(name) }
  func refreshAll() { for k in ["market", "news", "weather", "quant", "calendar", "mail"] { kick(k) } }
  func kickAll() { for k in loops.keys { kick(k) } }

  func pause() { paused = true }
  func resume() {
    guard paused else { return }
    paused = false
    kickAll()
  }

  private func anyOpen() -> Bool { Set(store.watch.map(Market.marketOf)).contains { Market.isOpen($0) } }

  // —— 各数据源 ——
  func refreshMarket() async {
    // 自选 + 每个行情组件自己设的那些
    var keys = store.watch
    for it in instances("market") { for k in store.config(it.id)["keys"] as? [String] ?? [] where !keys.contains(k) { keys.append(k) } }
    do {
      let fresh = try await Fetch.quotes(keys)
      var out: [String: Quote] = [:]
      for k in keys {
        guard var q = fresh[k] else { continue }
        // 失败时保留上次的数字，标成失败
        if q.failed, let prev = quotes[k], !prev.failed { var p = prev; p.failed = true; p.error = q.error; q = p }
        out[k] = q
      }
      quotes = out
      marketError = nil
      let alerts = Market.checkAlerts(Array(out.values), pct: store.alertPct, prices: store.priceAlerts, memo: &alertMemo, day: Brief.todayStr())
      for a in alerts { notify(a.title, a.body + "\n" + L("（延迟数据，仅供参考）")) }
    } catch {
      marketError = error.localizedDescription
      for k in quotes.keys { quotes[k]?.failed = true }
    }
    let now = nowMs()
    for k in quotes.keys { quotes[k]?.status = Market.quoteStatus(quotes[k], now) }
    marketAt = now
    scheduleButler()
  }

  func refreshNews() async {
    do { news = try await Fetch.news(store.newsSources) } catch {
      // 失败时保留旧数据
      if var n = news { n.error = error.localizedDescription; n.stale = true; news = n } else { news = NewsState(error: error.localizedDescription) }
    }
  }

  func refreshWeather() async {
    do { weather = try await Fetch.weather(store.city) } catch {
      if var w = weather { w.error = error.localizedDescription; w.stale = true; weather = w }
    }
    scheduleButler()
  }

  /** 系统日历（可以挑掉不想看的那几个）+ 订阅链接，合在一起 */
  func refreshCalendar() {
    let cs = calendarSettings
    var c = Fetch.calendar(apple: cs.apple, hidden: cs.hidden)
    if !icsEvents.isEmpty {
      if !c.ok && !cs.apple { c = CalendarState(ok: true) }
      if c.ok { c.events = (c.events + icsEvents).sorted { $0.start < $1.start } } else if cs.apple && !cs.ics.isEmpty { c = CalendarState(ok: true, events: icsEvents, error: c.error) }
    }
    calendar = c
    scheduleButler()
  }

  func askCalendar() async {
    calendar = await Fetch.askCalendar()
    scheduleButler()
  }

  /** 邮件从哪来：apple 邮件 App（默认）/ imap 邮箱 / off 不读 */
  var mailSource: String { (store.data["mail"] as? JSON)?["source"] as? String ?? "apple" }

  func refreshMail() async {
    switch mailSource {
    case "off": mail = MailState(ok: false, error: L("没有开邮件：到「设置 → 邮件」里选一个邮箱"))
    case "imap":
      if let a = IMAPMail.account(store) { mail = await IMAPMail.unread(a) } else { mail = MailState(ok: false, error: L("还没填邮箱地址：到「设置 → 邮件」里填")) }
    default: mail = await Fetch.mail()
    }
    await classifyMail()
    scheduleButler()
  }

  /** 读一封的正文：IMAP 邮箱直连服务器，「邮件」App 用 AppleScript */
  func mailBody(_ id: String, maxChars: Int = 8000) async -> Fetch.MailBody {
    if id.hasPrefix("imap:"), let a = IMAPMail.account(store) { return await IMAPMail.body(a, uid: String(id.dropFirst(5))) }
    return await Fetch.mailBody(id, maxChars: maxChars)
  }

  /** 在邮箱里打开这封：「邮件」App 直接定位；IMAP 邮箱打开网页版（Gmail 能定位到这封） */
  func openMail(_ id: String) {
    if id.hasPrefix("imap:"), let a = IMAPMail.account(store) {
      let msgid = mail?.items.first { $0.id == id }?.msgid ?? ""
      let u = IMAPMail.webURL(a, msgid: msgid)
      if !u.isEmpty { openURL(u) }
      return
    }
    openURL(MailAPI.messageUrl(id))
  }

  func refreshQuant() async {
    quant = await Fetch.quant(store.quantDir)
    scheduleButler()
  }

  func refreshBattery() async { battery = await Fetch.battery() }

  /** 新开一段浮层对话（换了 AI 也要新开：两家的上下文不通用） */
  func newOverlayChat() {
    overlayChat.cancel()
    overlayChat = Chat(agent: aiAgent)
  }

  /** 量化系统每 30 秒写一次 state.json：目录一变就读 */
  func watchQuant() {
    quantWatch?.cancel()
    let fd = open(store.quantDir + "/dashboard", O_EVTONLY)
    guard fd >= 0 else { return }
    let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename], queue: .main)
    var pending: DispatchWorkItem?
    src.setEventHandler { [weak self] in
      pending?.cancel()
      let w = DispatchWorkItem { Task { @MainActor in await self?.refreshQuant() } }
      pending = w
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: w)
    }
    src.setCancelHandler { close(fd) }
    src.resume()
    quantWatch = src
  }

  // —— 管家 ——
  private func scheduleButler() {
    butlerTimer?.cancel()
    butlerTimer = Task { [weak self] in
      try? await Task.sleep(nanoseconds: 250_000_000)
      guard let self, !Task.isCancelled else { return }
      var inp = Cands.Inputs()
      inp.quant = self.quant?.ok == true ? self.quant : nil
      inp.calendar = self.calendar
      inp.quotes = self.quotes
      inp.plans = self.store.plans
      inp.watch = self.store.watch
      inp.alertPct = self.store.alertPct
      inp.acctSize = self.store.acctSize
      inp.maxPerPct = self.store.maxPerPct
      inp.mail = self.mail?.ok == true ? self.mail?.items : nil
      inp.mailRules = self.mailRulesNow
      inp.soonMin = self.calendarSettings.soonMin
      inp.weather = self.weather
      var day = self.butler
      day.refresh(Cands.all(inp))
      if day.shown != self.butler.shown || day.droppedCount != self.butler.droppedCount || day.date != self.butler.date { self.butler = day }
    }
  }

  var hasNew: Bool { butler.hasNew(seen: store.butlerSeen) }

  /** 在浮层里点了管家 / 打开管家页 = 看过了，桌面上的蓝点熄灭。只留最近三天，别越攒越大 */
  func markSeen() {
    var seen = store.butlerSeen
    let now = nowMs()
    var changed = false
    for c in butler.shown where seen[c.id] == nil { seen[c.id] = now; changed = true }
    guard changed else { return }
    seen = seen.filter { now - $0.value <= 3 * 86400e3 }
    store.set(["butlerSeen": seen])
  }

  func snooze(_ id: String) { butler.snooze(id) }

  // —— 布局（每块显示器各一份；浮层里编辑的是浮层所在那块屏的） ——
  func layoutFor(_ key: String) -> Layout { key == "main" ? layout : (layouts[key] ?? normalize(presetLayout("minimal"))) }
  var editLayout: Layout { layoutFor(overlayKey) }
  func setLayout(_ L: Layout, key: String? = nil) {
    let k = key ?? overlayKey
    if k == "main" { layout = L; store.set(["layout": L.json]); return }
    layouts[k] = L
    var all = store.data["screenLayouts"] as? JSON ?? [:]
    all[k] = L.json
    store.set(["screenLayouts": all])
  }
  func moveWidget(_ id: String, _ col: Int, _ row: Int) { setLayout(move(editLayout.json, id, col, row)) }
  func resizeWidget(_ id: String, _ size: String) { setLayout(setSize(editLayout.json, id, size)) }
  func toggleWidget(_ id: String, _ on: Bool) { setLayout(toggle(editLayout.json, id, on)); kickWidgets() }
  func addWidget(_ type: String) { let r = addInstance(editLayout.json, type); setLayout(r.layout); kickWidgets(); if let id = r.id { configOpen = id } }
  func removeWidget(_ id: String) { setLayout(removeInstance(editLayout.json, id)) }
  func resetLayout() { setLayout(overlayKey == "main" ? normalize(store.data["preset"] as? String == nil ? DEFAULT_LAYOUT : presetLayout(store.data["preset"] as! String)) : normalize(presetLayout("minimal"))) }

  // —— 系统通知（涨跌提醒） ——
  private var asked = false
  func notify(_ title: String, _ body: String) {
    let c = UNUserNotificationCenter.current()
    let send = {
      let n = UNMutableNotificationContent()
      n.title = title
      n.body = body
      c.add(UNNotificationRequest(identifier: UUID().uuidString, content: n, trigger: nil))
    }
    if asked { send(); return }
    asked = true
    c.requestAuthorization(options: [.alert, .sound]) { ok, _ in if ok { send() } }
  }

  // —— 浮层里的点击 ——
  func openURL(_ s: String) {
    guard let u = URL(string: s), ["https", "http", "message"].contains(u.scheme ?? "") else { return }
    NSWorkspace.shared.open(u)
  }
  func openApp(_ bundleId: String) {
    guard let u = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else { return }
    NSWorkspace.shared.openApplication(at: u, configuration: .init())
  }
}
