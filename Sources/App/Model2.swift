// 数据中心的第二部分：新组件（待办、倒数日、加密货币、GitHub、订阅、照片、番茄钟）、主题、AI 判断重要邮件、权限兜底。
import AppKit
import EventKit

struct TodoItem: Identifiable, Equatable { let id: String; var title: String; var due: Double?; var list: String; var listId: String; var color: [Int]? }
struct TodoState { var ok: Bool; var items: [TodoItem] = []; var lists: [(id: String, title: String)] = []; var error: String?; var needAuth = false }

struct Pomodoro: Equatable {
  var total: Double = 25 * 60
  var end: Date?             // 正在跑：什么时候结束
  var left: Double = 25 * 60 // 暂停时还剩多少秒
  var running: Bool { end != nil }
  func remaining(_ now: Date = Date()) -> Double { end.map { max(0, $0.timeIntervalSince(now)) } ?? left }
}

/** 主题：强调色、字号、两侧渐隐的浓淡、组件有没有底 */
struct Theme { var accent: String, scale: Double, veil: Double, cards: Bool }

extension DeskModel {
  var theme: Theme {
    let t = store.data["theme"] as? JSON ?? [:]
    return Theme(accent: t["accent"] as? String ?? "blue", scale: num(t["scale"]) ?? 1, veil: num(t["veil"]) ?? 1, cards: t["style"] as? String == "cards")
  }
  func setTheme(_ patch: JSON) {
    var t = store.data["theme"] as? JSON ?? [:]
    for (k, v) in patch { t[k] = v }
    store.set(["theme": t])
  }

  /** 所有屏上开着的某种组件（同一种可以有好几个） */
  func instances(_ type: String) -> [LayoutItem] {
    ([layout] + Array(layouts.values)).flatMap(\.items).filter { $0.on && $0.type == type }
      .reduce(into: [LayoutItem]()) { acc, x in if !acc.contains(where: { $0.id == x.id }) { acc.append(x) } }
  }

  /** 设置或布局变了：马上把相关的数据取一遍 */
  func kickWidgets() { for k in ["crypto", "github", "feeds", "cities", "todos", "photos"] { kick(k) } }

  // —— 加密货币（CoinGecko，免费、不用注册） ——
  func refreshCrypto() async {
    for it in instances("crypto") {
      let c = store.config(it.id)
      let ids = (c["coins"] as? [String] ?? ["bitcoin", "ethereum"]).map(Crypto.id)
      let vs = c["vs"] as? String ?? "usd"
      guard let d = try? await Fetch.get(Crypto.url(ids, vs: vs)), let j = (try? JSONSerialization.jsonObject(with: d)) as? JSON else { continue }
      crypto[it.id] = Crypto.parse(j, ids: ids, vs: vs)
    }
  }

  // —— GitHub（公开接口，不登录每小时 60 次，所以半小时取一次） ——
  func refreshRepos() async {
    for it in instances("github") {
      var out: [RepoInfo] = []
      for r in store.config(it.id)["repos"] as? [String] ?? [] {
        guard let u = GitHubAPI.repoURL(r), let d = try? await Fetch.get(u), let j = (try? JSONSerialization.jsonObject(with: d)) as? JSON, var info = GitHubAPI.parseRepo(j) else { continue }
        if let ru = GitHubAPI.releasesURL(r), let rd = try? await Fetch.get(ru), let rel = (try? JSONSerialization.jsonObject(with: rd)) as? [JSON] {
          info.downloads = GitHubAPI.totalDownloads(rel)
        }
        out.append(info)
      }
      repos[it.id] = out
    }
  }

  // —— 订阅（任意 RSS / Atom 地址） ——
  func refreshFeeds() async {
    for it in instances("rss") {
      let c = store.config(it.id)
      guard let s = c["url"] as? String, let u = URL(string: s) else { continue }
      do {
        let d = try await Fetch.get(u, headers: ["User-Agent": "Mozilla/5.0 DeskHub"])
        let xml = String(data: d, encoding: .utf8) ?? String(decoding: d, as: UTF8.self)
        let title = (c["title"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? News.feedTitle(xml) ?? u.host ?? ""
        feeds[it.id] = NewsState(items: Array(News.parseFeed(xml, source: title).sorted { $0.ts > $1.ts }.prefix(30)), at: nowMs())
      } catch {
        var old = feeds[it.id] ?? NewsState()
        old.error = error.localizedDescription
        feeds[it.id] = old
      }
    }
  }

  // —— 天气组件各自的城市 ——
  func refreshCities() async {
    for it in instances("weather") {
      guard let c = store.config(it.id)["city"] as? JSON, let name = c["name"] as? String, let lat = num(c["lat"]), let lon = num(c["lon"]) else { continue }
      if let w = try? await Fetch.weather((name, lat, lon)) { cityWeather[it.id] = w }
    }
  }

  // —— 待办：系统「提醒事项」里没完成的（EventKit，第一次要授权） ——
  func refreshTodos() {
    guard !instances("todo").isEmpty else { return }
    let st = EKEventStore.authorizationStatus(for: .reminder)
    guard st == .fullAccess else {
      todos = TodoState(ok: false, error: st == .notDetermined ? L("还没授权读取提醒事项") : L("没有提醒事项的权限"), needAuth: st == .notDetermined)
      return
    }
    let s = Fetch.eventStore
    let lists = s.calendars(for: .reminder)
    let pred = s.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: lists)
    s.fetchReminders(matching: pred) { rs in
      let items = (rs ?? []).prefix(300).map { r -> TodoItem in
        let c = r.calendar?.color?.usingColorSpace(.sRGB)
        return TodoItem(id: r.calendarItemIdentifier, title: r.title ?? "", due: r.dueDateComponents?.date.map { $0.timeIntervalSince1970 * 1000 },
                        list: r.calendar?.title ?? "", listId: r.calendar?.calendarIdentifier ?? "",
                        color: c.map { [Int($0.redComponent * 255), Int($0.greenComponent * 255), Int($0.blueComponent * 255)] })
      }.sorted { ($0.due ?? .greatestFiniteMagnitude) < ($1.due ?? .greatestFiniteMagnitude) }
      let ls = lists.map { ($0.calendarIdentifier, $0.title) }
      Task { @MainActor in self.todos = TodoState(ok: true, items: items, lists: ls) }
    }
  }

  func askReminders() async {
    _ = try? await Fetch.eventStore.requestFullAccessToReminders()
    refreshTodos()
  }

  /** 在浮层里勾掉一条待办（写回「提醒事项」，这是你自己点的） */
  func completeTodo(_ id: String) {
    guard let r = Fetch.eventStore.calendarItem(withIdentifier: id) as? EKReminder else { return }
    r.isCompleted = true
    try? Fetch.eventStore.save(r, commit: true)
    todos?.items.removeAll { $0.id == id }
  }

  // —— 照片：从你选的文件夹里轮着显示 ——
  func rotatePhotos() {
    for it in instances("photo") {
      let dir = store.config(it.id)["folder"] as? String ?? (NSHomeDirectory() + "/Pictures")
      let files = ((try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? [])
        .filter { ["jpg", "jpeg", "png", "heic", "webp", "tiff", "gif"].contains(($0 as NSString).pathExtension.lowercased()) && !$0.hasPrefix(".") }
      guard let f = files.randomElement() else { photos[it.id] = ""; continue }
      photos[it.id] = dir + "/" + f
    }
  }

  // —— 番茄钟 ——
  func pomoStart() {
    var p = pomo
    p.end = Date().addingTimeInterval(p.left)
    pomo = p
    let end = p.end!
    DispatchQueue.main.asyncAfter(deadline: .now() + p.left) { [weak self] in
      guard let self, self.pomo.end == end else { return }
      self.pomo = Pomodoro(total: self.pomo.total, end: nil, left: self.pomo.total)
      self.notify(L("番茄钟"), L("时间到了，休息一下"))
    }
  }
  func pomoPause() { var p = pomo; p.left = p.remaining(); p.end = nil; pomo = p }
  func pomoReset(_ minutes: Double? = nil) { let t = (minutes ?? pomo.total / 60) * 60; pomo = Pomodoro(total: t, end: nil, left: t) }

  // —— 让 AI 判断哪些邮件重要（用户在设置里打开才会做；只发发件人和主题，不发正文） ——
  var mailRulesNow: Cands.MailRules { var r = store.mailRules; r.aiHits = aiImportant; return r }

  func classifyMail() async {
    guard store.aiMail, Keychain.hasKey, let m = mail, m.ok else { return }
    let fresh = m.items.filter { !aiAsked.contains($0.id) && !$0.id.isEmpty }.prefix(12)
    guard !fresh.isEmpty else { return }
    for x in fresh { aiAsked.insert(x.id) }
    let list = fresh.enumerated().map { "\($0.offset + 1). 发件人：\($0.element.name) <\($0.element.email)>；主题：\($0.element.subject)" }.joined(separator: "\n")
    let prompt = "下面是我的几封未读邮件（只有发件人和主题）。哪些是「真人在等我回复、或者需要我做点什么、或者有截止时间」的？广告、促销、通知、订阅一律不算。只输出编号的 JSON 数组，比如 [1,3]；都不算就输出 []。\n\n" + list
    guard let reply = try? await DeepSeek.complete([["role": "user", "content": prompt]], model: "deepseek-chat"),
          let arr = reply.match("\\[[\\d,\\s]*\\]")?[0].flatMap({ try? JSONSerialization.jsonObject(with: Data($0.utf8)) }) as? [Int] else { return }
    for i in arr where i >= 1 && i <= fresh.count { aiImportant.insert(Array(fresh)[i - 1].id) }
  }

  // —— 权限：被拒绝过之后，系统不会再弹框，只能让用户去系统设置里打开 ——
  func openPrivacy(_ pane: String) {
    if let u = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") { NSWorkspace.shared.open(u) }
  }

  // —— 检查更新（一天最多问一次 GitHub；有新版只提示，不自动下载安装） ——
  static var currentVersion: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0" }

  func checkUpdate(manual: Bool = false) async {
    let last = num(store.data["lastUpdateCheck"]) ?? 0
    guard manual || nowMs() - last > 20 * 3600e3, !measuring, !isSnapshot else { return }
    if manual { updateStatus = L("正在检查…") }
    guard let d = try? await Fetch.get(Update.latestURL, headers: ["Accept": "application/vnd.github+json"]),
          let j = (try? JSONSerialization.jsonObject(with: d)) as? JSON else {
      if manual { updateStatus = L("检查失败，稍后再试") }
      return
    }
    store.set(["lastUpdateCheck": nowMs()])
    update = Update.newer(Update.parse(j), than: DeskModel.currentVersion, skip: store.data["skipVersion"] as? String)
    if let u = update {
      updateStatus = L("有新版本 %@", u.version)
      // 每个新版本只发一次系统通知
      if store.data["notifiedVersion"] as? String != u.version {
        store.set(["notifiedVersion": u.version])
        notify(L("桌面信息中心有新版本 %@", u.version), L("在浮层右上角或「设置 → 外观」里点一下去下载"))
      }
    } else if manual { updateStatus = L("已经是最新版本") }
  }

  func skipUpdate() {
    guard let u = update else { return }
    store.set(["skipVersion": u.version])
    update = nil
    updateStatus = ""
  }
}
