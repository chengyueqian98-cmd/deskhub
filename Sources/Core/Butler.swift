// 管家：从 Electron 版 brief.js（该不该说）+ candidates.js / plans.js（候选事件）+ aiSay.js 的模板句（怎么说）移植。
//
// 判断只用两个轴：可执行性 actionable（他现在能不能做点什么）× 意外性 surprise（他是不是本来就知道），各 0–3。
// 只有「可执行 且 意外」才配打断他；其余降级，不丢弃。配额只管打断：通知 1 条/天、浮层 3 条/天，超额往下降。
// 只做展示和提醒，不做买卖、不给建议——话术里只陈述事实，选项只能是时间或他自己的参数。
import Foundation

struct CandAction: Equatable { let label: String, type: String, arg: String }

struct Candidate: Equatable {
  var id: String
  var kind: String
  var actionable: Int
  var surprise: Int
  var urgency = 0
  var facts: [String: String] = [:]
  var evidence: [String] = []
  var action: CandAction?
  // 下面三个由 plan() 填
  var score = 0
  var level = ""
  var downgraded = false
}

enum Brief {
  static let defaultLimits = (notify: 1, overlay: 3)
  static let seenHours = 12.0

  private static func clamp3(_ n: Int) -> Int { max(0, min(3, n)) }

  static func scoreOf(_ c: Candidate) -> Int { clamp3(c.actionable) * clamp3(c.surprise) }

  /** 四象限：notify 现在就说 / overlay 排进简报 / desk 只挂着 / nil 永不出现 */
  static func levelOf(_ c: Candidate) -> String? {
    let a = clamp3(c.actionable), s = clamp3(c.surprise)
    if a >= 2 && s >= 2 { return "notify" }
    if a >= 2 { return "overlay" }
    if s >= 2 { return "desk" }
    return nil
  }

  static func todayStr(_ now: Double = nowMs()) -> String { let t = ymd(now); return "\(t.y)-\(t.m)-\(t.d)" }

  struct State: Equatable {
    var date: String
    var notify = 0
    var overlay = 0
    var seen: [String: Double] = [:]
  }

  /** 同一天再跑一次：保留已用配额和已说过的 id；跨天则清零 */
  static func rollState(_ s: State?, _ now: Double = nowMs()) -> State {
    let date = todayStr(now)
    guard let s, s.date == date else { return State(date: date) }
    return s
  }

  struct Result {
    var date: String
    var notify: [Candidate] = []
    var overlay: [Candidate] = []
    var desk: [Candidate] = []
    var state: State
    var notes: [String] = []
    var dropped: [(id: String, why: String)] = []
    var flat: [Candidate] { (notify + overlay + desk).enumerated().sorted { $0.element.score != $1.element.score ? $0.element.score > $1.element.score : $0.offset < $1.offset }.map(\.element) }
  }

  /** 排优先级 → 分派到三层 → 超额降级。永远不丢信息，只降低打扰级别 */
  static func plan(_ cands: [Candidate], state prev: State? = nil, now: Double = nowMs(), limits: (notify: Int, overlay: Int) = defaultLimits) -> Result {
    var r = Result(date: "", state: rollState(prev, now))
    r.date = r.state.date
    var alive: [(Candidate, Int)] = []
    for c in cands {
      if c.id.isEmpty { r.dropped.append(("(no id)", "no-id")); continue }
      if let last = r.state.seen[c.id], now - last < seenHours * 3600e3 { r.dropped.append((c.id, "repeat")); continue }
      guard let lv = levelOf(c) else { r.dropped.append((c.id, "never")); continue }
      var x = c
      x.score = scoreOf(c); x.level = lv
      alive.append((x, alive.count))
    }
    // 同分时不按 id 字母序：先看 urgency，再看传入顺序（数据源自己排的优先级）
    alive.sort { a, b in
      if a.0.score != b.0.score { return a.0.score > b.0.score }
      if clamp3(a.0.urgency) != clamp3(b.0.urgency) { return clamp3(a.0.urgency) > clamp3(b.0.urgency) }
      return a.1 < b.1
    }
    for (c, _) in alive {
      var lv = c.level
      if lv == "notify" && r.state.notify >= limits.notify { r.notes.append("\(c.id) 通知配额已满 → 降级为 overlay"); lv = "overlay" }
      if lv == "overlay" && r.state.overlay >= limits.overlay { r.notes.append("\(c.id) 浮层配额已满 → 降级为 desk"); lv = "desk" }
      if lv == "notify" { r.state.notify += 1 }
      if lv == "overlay" { r.state.overlay += 1 }
      r.state.seen[c.id] = now
      var x = c
      x.downgraded = c.level != lv
      x.level = lv
      switch lv {
      case "notify": r.notify.append(x)
      case "overlay": r.overlay.append(x)
      default: r.desk.append(x)
      }
    }
    return r
  }

  // —— 怎么说：模板句（AI 改写在第 4 阶段；模板永远兜底，宁可说得笨，不能说得错） ——
  // 英文名和中文之间要有空格，否则「School Registrar在等你」读起来是糊的
  private static func gap(_ s: String?) -> String {
    let t = s ?? ""
    return t.test("[A-Za-z0-9)\\]]$") ? t + " " : t
  }

  static func say(_ c: Candidate) -> String {
    let f = c.facts
    let g = { (k: String) in f[k] ?? "" }
    if appLang == "en" { return sayEn(c) }
    switch c.kind {
    case "mail_waiting": return "\(gap(f["from"]))在等你：\(g("subject"))"
    case "mail_money": return "\(gap(f["from"]))来信：\(g("subject"))"
    case "risk_alert": return "\(g("name")) \(g("pct"))，已破止损线。现在看，还是收盘再看？"
    case "risk_stale": return "\(g("name")) \(g("pct"))，量化数据停在 \(g("asOf"))，不是今天的。"
    case "plan_hit": return "\(g("name")) \(g("price"))，\(g("dir"))你设的\(g("which")) \(g("target"))。"
    case "event_soon": return "\(g("title")) \(g("at")) 开始\(g("place").isEmpty ? "" : "，在" + g("place"))。现在走，还是再看十分钟？"
    case "watch_move": return "\(g("name")) 今天 \(g("pct"))。"
    case "position_cap": return "\(g("name")) 占 \(g("share"))，超过你设的单票上限 \(g("cap"))。要调上限，还是先记着？"
    case "day_ahead": return "今天 \(g("temp")) 度\(g("rain").isEmpty ? "" : "、" + g("rain"))，\(f["note"] ?? "照常")"
    default: return "\(f["subject"] ?? f["title"] ?? "有一件事")，要不要看？"
    }
  }

  static func sayEn(_ c: Candidate) -> String {
    let f = c.facts
    let g = { (k: String) in f[k] ?? "" }
    switch c.kind {
    case "mail_waiting": return "\(g("from")) is waiting on you: \(g("subject"))"
    case "mail_money": return "From \(g("from")): \(g("subject"))"
    case "risk_alert": return "\(g("name")) \(g("pct")), past the stop-loss line. Look now, or after the close?"
    case "risk_stale": return "\(g("name")) \(g("pct")) — trading data stopped at \(g("asOf")), not today's."
    case "plan_hit": return "\(g("name")) \(g("price")) \(["跌破": "fell below", "涨过": "rose above", "快到": "is near"][g("dir")] ?? g("dir")) your \(g("which") == "买入价" ? "buy price" : "sell price") \(g("target"))."
    case "event_soon": return "\(g("title")) starts at \(g("at"))\(g("place").isEmpty ? "" : " at " + g("place")). Leave now, or ten more minutes?"
    case "watch_move": return "\(g("name")) \(g("pct")) today."
    case "position_cap": return "\(g("name")) is \(g("share")) of your account, above your \(g("cap")) cap. Change the cap, or keep a note?"
    case "day_ahead": return "\(g("temp"))° today\(g("rain").isEmpty ? "" : ", rain likely"), \(g("note") == "记得带伞" ? "take an umbrella" : "dress warmly")"
    default: return "\(f["subject"] ?? f["title"] ?? "Something came up") — take a look?"
    }
  }

  /** 「重要」= 可执行且意外（和落进「现在就说」那一格的标准一样）。桌面上的管家只说这些 */
  static func important(_ c: Candidate) -> Bool { c.actionable >= 2 && c.surprise >= 2 }
}

// —— 候选事件：把各数据源变成「可能值得说的事」 ——
enum Cands {
  static let stopLoss = -8.0              // 和量化系统 config.py 的 RISK.stop_loss_pct 对齐
  static let soonMin = 20.0               // 日程开始前多少分钟内才提醒
  static let mailWithin = 3 * 86400e3     // 只关心近 3 天
  static let quantStaleHours = 6.0
  static let watchMoveMax = 3
  /** 「有人在等你」的名单不再写死：由用户在首次引导或设置里填（名字、邮箱、关键词都行） */
  struct MailRules {
    var contacts: [String] = []
    var money = true                 // 银行 / 转账 / 账单那一档
    var aiHits: Set<String> = []     // 让 AI 判断过「重要」的邮件 id
  }
  static let mailMoney = ["zelle", "venmo", "paypal", "wire transfer", "payment", "转账", "付款", "账单", "\\bstatement\\b",
                          "bank of america", "\\bchase\\b", "wells fargo", "\\bciti(bank)?\\b", "银行", "tuition", "学费"]
  static let mailMoneyAlert = ["fraud", "suspicious", "unauthori[sz]ed", "security alert", "locked", "overdraw", "past due", "欺诈", "异常", "冻结", "逾期"]

  private static func any(_ pats: [String], _ text: String) -> Bool { pats.contains { text.test($0, .caseInsensitive) } }

  static func ago(_ ts: Double, _ now: Double) -> String {
    let m = Int(((now - ts) / 60000).rounded())
    if m < 1 { return L("刚刚") }
    if m < 60 { return L("%@ 分钟前", "\(m)") }
    let h = Int((Double(m) / 60).rounded())
    if h < 24 { return L("%@ 小时前", "\(h)") }
    return L("%@ 天前", "\(Int((Double(h) / 24).rounded()))")
  }

  /** 有人在等你：未读 + 近 3 天 + 发件人或主题命中你填的名单（或 AI 判断为重要）；银行/转账/账单是第二档 */
  static func mail(_ items: [MailItem]?, _ now: Double = nowMs(), rules: MailRules = MailRules()) -> [Candidate] {
    let hit = rules.contacts.map { $0.trimmed() }.filter { !$0.isEmpty }.map { NSRegularExpression.escapedPattern(for: $0) }
    var out: [Candidate] = []
    for x in items ?? [] {
      guard let ts = x.ts, ts != 0, now - ts < mailWithin else { continue }
      let text = "\(x.name) \(x.email) \(x.subject)"
      let id = "mail:" + (x.id.isEmpty ? jsNum(ts) : x.id)
      let facts = ["from": x.name.isEmpty ? x.email : x.name, "subject": x.subject]
      let evidence = [x.email, ago(ts, now), x.account].filter { !$0.isEmpty }
      if any(hit, text) || rules.aiHits.contains(x.id) {
        out.append(Candidate(id: id, kind: "mail_waiting", actionable: 3, surprise: 3, urgency: 2, facts: facts, evidence: evidence,
                             action: x.id.isEmpty ? nil : CandAction(label: L("去回"), type: "mail", arg: x.id)))
      } else if rules.money && any(mailMoney, text) {
        let alert = any(mailMoneyAlert, text)
        out.append(Candidate(id: id, kind: "mail_money", actionable: alert ? 3 : 2, surprise: alert ? 3 : 1, urgency: alert ? 3 : 1, facts: facts, evidence: evidence,
                             action: x.id.isEmpty ? nil : CandAction(label: L("去看"), type: "mail", arg: x.id)))
      }
    }
    return out
  }

  private static let quantTime: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "yyyy-MM-dd HH:mm:ss"
    return f
  }()

  /** 持仓：破了止损，或者量化系统给了做 T 信号。停机或数据太老 → 旧账（只挂着，不喊「现在」） */
  static func risk(_ quant: QuantState?, _ now: Double = nowMs()) -> [Candidate] {
    guard let quant else { return [] }
    var out: [Candidate] = []
    for p in quant.positions {
      guard let pnlPct = p.pnlPct else { continue }
      let stopped = pnlPct <= stopLoss
      let signal = p.tType != "none" && !p.tType.isEmpty
      if !stopped && !signal { continue }
      let pct = (pnlPct >= 0 ? "+" : "") + jsNum(pnlPct) + "%"
      let at = quant.updatedAt.flatMap { quantTime.date(from: $0) }.map { $0.timeIntervalSince1970 * 1000 }
      let hours = at.map { (now - $0) / 3600e3 }
      let asOf = at.map { a -> String in let t = ymd(a); return "\(t.m)-\(pad2(t.d)) \(pad2(t.h)):\(pad2(t.mi))" } ?? ""
      let stale = quant.running == false || (hours.map { $0 > quantStaleHours } ?? false)
      var facts = ["name": p.name, "pct": pct]
      if stale && !asOf.isEmpty { facts["asOf"] = asOf }
      let ev: [String] = [
        "\(p.code) \(p.name)", L("现价 %@", p.price.map(jsNum) ?? "—"), L("成本 %@", p.cost.map(jsNum) ?? "—"),
        L("浮亏 %@", p.pnl.map(jsNum) ?? "—"), stopped ? L("已破 %@%% 止损线", jsNum(stopLoss)) : p.tMsg,
        asOf.isEmpty ? "" : L("数据 %@", asOf), quant.running == false ? L("量化系统已停机") : "",
        (hours ?? 0) > 24 ? L("这批数据已 %@ 小时没更新", "\(Int(hours!.rounded()))") : "",
      ].filter { !$0.isEmpty }
      out.append(Candidate(
        id: "risk:\(p.code):\(stopped ? "sl" : p.tType)\(stale ? ":stale" : "")",
        kind: stale && !asOf.isEmpty ? "risk_stale" : "risk_alert",
        actionable: stale ? 1 : 3, surprise: stale ? 2 : (stopped ? 3 : 2), urgency: stale ? 1 : (stopped ? 3 : 2),
        facts: facts, evidence: ev, action: CandAction(label: L("看持仓"), type: "nav", arg: "stock")))
    }
    return out
  }

  /** 天气：要下雨或者很冷才值得占一行；晴天不打扰 */
  static func day(_ w: Weather?, _ now: Double = nowMs()) -> [Candidate] {
    guard let w else { return [] }
    let rain = w.days.first?.rain ?? 0
    let rainy = rain >= 50, cold = w.now.temp <= 6
    if !rainy && !cold { return [] }
    return [Candidate(
      id: "day:" + Brief.todayStr(now), kind: "day_ahead", actionable: 2, surprise: 1, urgency: 1,
      facts: ["temp": "\(w.now.temp)", "rain": rainy ? (w.days.first?.text ?? "有雨") : "", "note": rainy ? "记得带伞" : "多穿点"],
      evidence: [w.city, L(w.now.text), L("体感 %@ 度", "\(w.now.feels)"), L("降水 %@%%", "\(rain)")].filter { !$0.isEmpty })]
  }

  /** 日程：快开始了才说（20 分钟内）。只说「开始了」，不替你判断该不该去 */
  static func calendar(_ c: CalendarState?, _ now: Double = nowMs()) -> [Candidate] {
    guard let c, c.ok else { return [] }
    var out: [Candidate] = []
    for e in c.events where !e.allDay && e.start != 0 {
      let min = (e.start - now) / 60000
      guard min >= 0 && min <= soonMin else { continue }
      let t = ymd(e.start)
      let at = "\(pad2(t.h)):\(pad2(t.mi))"
      out.append(Candidate(
        id: "cal:\(e.id.isEmpty ? e.title : e.id):\(jsNum(e.start))", kind: "event_soon", actionable: 3, surprise: 1, urgency: 3,
        facts: ["title": e.title, "at": at, "place": e.location],
        evidence: [L("%@ 开始", at), e.location.isEmpty ? "" : L("地点 %@", e.location), L("%@ 分钟后", "\(Int(min.rounded()))")].filter { !$0.isEmpty }))
    }
    return out
  }

  /** 自选异动：涨跌幅超过你自己设的阈值。只进「挂着」那一层，不当通知用 */
  static func watch(_ quotes: [String: Quote], _ keys: [String], _ alertPct: Double, _ now: Double = nowMs()) -> [Candidate] {
    guard alertPct > 0 else { return [] }
    let day = Brief.todayStr(now)
    return keys.compactMap { quotes[$0] }
      .filter { !$0.failed && $0.pct != nil && abs($0.pct!) >= alertPct }
      .sorted { abs($0.pct!) > abs($1.pct!) }
      .prefix(watchMoveMax)
      .map { q in
        Candidate(id: "move:\(q.key):\(day)", kind: "watch_move", actionable: 1, surprise: 2, urgency: 1,
                  facts: ["name": q.name, "pct": (q.pct! >= 0 ? "+" : "") + jsNum(q.pct!) + "%"],
                  evidence: ["\(q.code) \(q.name)", L("现价 %@", q.price.map(jsNum) ?? "—"), L("超过你设的 %@%% 阈值", jsNum(alertPct))],
                  action: CandAction(label: L("看自选"), type: "nav", arg: "stock"))
      }
  }

  struct Inputs {
    var quant: QuantState?
    var calendar: CalendarState?
    var quotes: [String: Quote] = [:]
    var plans: [String: Any] = [:]
    var watch: [String] = []
    var alertPct = 3.0
    var acctSize = 0.0
    var maxPerPct = 20.0
    var mail: [MailItem]?
    var mailRules = MailRules()
    var weather: Weather?
  }

  /** 全部候选。顺序即同分时的默认优先级 */
  static func all(_ s: Inputs, _ now: Double = nowMs()) -> [Candidate] {
    risk(s.quant, now)                                           // 钱最急
      + calendar(s.calendar, now)                                // 马上要开始了
      + Plans.candidates(s.quotes, s.plans, now)                 // 到你设的价了
      + watch(s.quotes, s.watch, s.alertPct, now)                // 自选异动，只挂着
      + Plans.capCandidates(s.quant, acctSize: s.acctSize, maxPerPct: s.maxPerPct, now)
      + mail(s.mail, now, rules: s.mailRules)
      + day(s.weather, now)
  }
}

// —— 计划：你自己给自选股填的买入价 / 卖出价。只替你盯着，不给建议 ——
enum Plans {
  static let near = 0.02    // 距离目标 2% 以内算「快到了」

  struct Plan: Equatable {
    var buy: Double?
    var sell: Double?
    var note: String
  }

  private static func pos(_ v: Any?) -> Double? { num(v).flatMap { $0 > 0 ? $0 : nil } }

  static func norm(_ p: Any?) -> Plan {
    let o = p as? JSON ?? [:]
    return Plan(buy: pos(o["buy"]), sell: pos(o["sell"]), note: (o["note"] as? String)?.head(80) ?? "")
  }

  struct PlanState {
    var side: String
    var dist: Double?
    var buy: Double?
    var sell: Double?
  }

  /** under_buy / over_sell（到价）、near_buy / near_sell（差 2% 以内）、mid、none */
  static func state(_ plan: Plan, _ price: Double?) -> PlanState {
    guard let px = price, px > 0 else { return PlanState(side: "none", dist: nil, buy: plan.buy, sell: plan.sell) }
    if plan.buy == nil && plan.sell == nil { return PlanState(side: "none", dist: nil, buy: nil, sell: nil) }
    if let b = plan.buy, px <= b { return PlanState(side: "under_buy", dist: (px - b) / b, buy: b, sell: nil) }
    if let s = plan.sell, px >= s { return PlanState(side: "over_sell", dist: (px - s) / s, buy: nil, sell: s) }
    if let b = plan.buy, (px - b) / b <= near { return PlanState(side: "near_buy", dist: (px - b) / b, buy: b, sell: nil) }
    if let s = plan.sell, (s - px) / s <= near { return PlanState(side: "near_sell", dist: (px - s) / s, buy: nil, sell: s) }
    return PlanState(side: "mid", dist: nil, buy: plan.buy, sell: plan.sell)
  }

  /** 表格里「距买入」那一列：只说位置，不说该不该买 */
  static func distanceText(_ plan: Plan, _ price: Double?) -> String {
    let s = state(plan, price)
    guard s.side != "none", s.side != "mid", let dist = s.dist else { return "" }
    let d = String(format: "%.1f", abs(dist) * 100) + "%"
    switch s.side {
    case "under_buy": return L("已低于买入价 ") + d
    case "over_sell": return L("已高于卖出价 ") + d
    case "near_buy": return L("距买入 ") + d
    default: return L("距卖出 ") + d
    }
  }

  /** 到价 / 快到了 → 候选事件。同一个价位每天最多说一次（id 里带日期） */
  static func candidates(_ quotes: [String: Quote], _ plans: [String: Any], _ now: Double = nowMs()) -> [Candidate] {
    let day = Brief.todayStr(now)
    var out: [Candidate] = []
    for key in plans.keys.sorted() {
      guard let q = quotes[key], !q.failed, let price = q.price else { continue }
      let plan = norm(plans[key])
      let s = state(plan, price)
      if s.side == "none" || s.side == "mid" { continue }
      let hit = s.side == "under_buy" || s.side == "over_sell"
      let dir = s.side == "under_buy" ? "跌破" : s.side == "over_sell" ? "涨过" : "快到"
      let which = s.buy != nil && (s.side == "under_buy" || s.side == "near_buy") ? "买入价" : "卖出价"
      let target = which == "买入价" ? s.buy : s.sell
      let name = q.name.isEmpty ? (q.code.isEmpty ? key : q.code) : q.name
      out.append(Candidate(
        id: "plan:\(key):\(s.side):\(day)", kind: "plan_hit", actionable: hit ? 3 : 2, surprise: hit ? 2 : 1, urgency: hit ? 2 : 1,
        facts: ["name": name, "price": jsNum(price), "dir": dir, "which": which, "target": target.map(jsNum) ?? ""],
        evidence: ["\(q.code) \(q.name)".trimmed(), L("现价 %@", jsNum(price)), "\(L(which)) \(target.map(jsNum) ?? "")",
                   plan.note.isEmpty ? "" : L("观察：") + plan.note, q.status == "live" ? L("交易中") : L("已收盘，价格不是最新的")].filter { !$0.isEmpty },
        action: CandAction(label: L("看自选"), type: "nav", arg: "stock")))
    }
    return out
  }

  /** 按「你自己填的账户金额」算的仓位（和量化系统那套口径并列，不替代） */
  static func shareOf(_ mv: Double?, _ acct: Double?) -> Double? {
    guard let mv, let acct, acct > 0, mv >= 0 else { return nil }
    return round2(mv / acct * 100, 1)
  }

  /** 单票占比超过你自己设的上限 → 一条只挂不弹的候选 */
  static func capCandidates(_ quant: QuantState?, acctSize: Double, maxPerPct: Double, _ now: Double = nowMs()) -> [Candidate] {
    guard acctSize > 0, maxPerPct > 0, let quant else { return [] }
    let day = Brief.todayStr(now)
    return quant.positions.compactMap { p in
      guard let share = shareOf(p.mv, acctSize), share > maxPerPct else { return nil }
      return Candidate(
        id: "cap:\(p.code):\(day)", kind: "position_cap", actionable: 2, surprise: 1, urgency: 1,
        facts: ["name": p.name, "share": jsNum(share) + "%", "cap": jsNum(maxPerPct) + "%"],
        evidence: ["\(p.code) \(p.name)", L("市值 %@", p.mv.map(jsNum) ?? "—"), L("你填的账户金额 %@", jsNum(acctSize)), L("单票上限 %@%%", jsNum(maxPerPct)),
                   share > 100 ? L("占比超过 100%，说明你填的账户金额比当前市值还小") : ""].filter { !$0.isEmpty },
        action: CandAction(label: L("看持仓"), type: "nav", arg: "stock"))
    }
  }
}

// —— 管家的「今天」：跨刷新保留配额和已说过的事（从 Electron 版 butler.js 的 refresh 移植） ——
struct ButlerDay {
  var state: Brief.State?
  var shown: [Candidate] = []     // 今天已经显示过的，只增不减（「晚点」除外）
  var notes: [String] = []
  var droppedCount = 0
  var date = ""

  /** 新数据来了：没有新事情就不重排（重排会消耗配额）；有就排一次，把新说的加进 shown */
  mutating func refresh(_ cands: [Candidate], now: Double = nowMs()) {
    let today = Brief.todayStr(now)
    if date != today { shown = []; date = today; state = nil }
    if let st = state, cands.allSatisfy({ st.seen[$0.id] != nil }) { return }
    let r = Brief.plan(cands, state: state, now: now)
    state = r.state
    notes = r.notes
    droppedCount = r.dropped.count
    for c in r.flat where !shown.contains(where: { $0.id == c.id }) { shown.append(c) }
  }

  mutating func snooze(_ id: String) { shown.removeAll { $0.id == id } }

  var sorted: [Candidate] { shown.enumerated().sorted { $0.element.score != $1.element.score ? $0.element.score > $1.element.score : $0.offset < $1.offset }.map(\.element) }
  var important: [Candidate] { sorted.filter(Brief.important) }
  var looked: Int { shown.count + droppedCount }

  /** 有「重要且还没在浮层里点开过」的事 → 桌面上闪蓝 */
  func hasNew(seen: [String: Double]) -> Bool { shown.contains { Brief.important($0) && seen[$0.id] == nil } }
}
