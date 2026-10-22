// AI：DeepSeek（直接走 HTTPS，几乎不占内存）和 Claude Code（命令行，每问一次起一个进程，答完就退出）。
// OpenClaw 不再接（它要常驻一个约 1 GB 的网关）——用户 2026-10-22 定的。
//
// DeepSeek 的 API Key 只存在系统钥匙串里：不进 desk.json、不进日志、界面只能问「有没有」。
import AppKit
import Security

// —— 钥匙串 ——
enum Keychain {
  private static let service = "com.qianshengyue.desktophub.deepseek"
  private static let account = "api-key"
  private static func base(_ service: String, _ account: String) -> [String: Any] {
    [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
  }

  /** 默认是 DeepSeek 的 Key；邮箱的应用专用密码用另一个服务名、账号是邮箱地址 */
  static func read(service: String = service, account: String = account) -> String? {
    var q = base(service, account)
    q[kSecReturnData as String] = true
    q[kSecMatchLimit as String] = kSecMatchLimitOne
    var out: CFTypeRef?
    guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
    return String(data: d, encoding: .utf8)
  }

  static func save(_ key: String, service: String = service, account: String = account) -> Bool {
    clear(service: service, account: account)
    var q = base(service, account)
    q[kSecValueData as String] = Data(key.utf8)
    q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    return SecItemAdd(q as CFDictionary, nil) == errSecSuccess
  }

  @discardableResult static func clear(service: String = service, account: String = account) -> Bool { SecItemDelete(base(service, account) as CFDictionary) == errSecSuccess }
  static var hasKey: Bool { read() != nil }
}

// —— DeepSeek ——
enum DeepSeek {
  static let endpoint = URL(string: "https://api.deepseek.com/chat/completions")!
  static let models = [("deepseek-chat", "对话（快、便宜）"), ("deepseek-reasoner", "推理（慢一点，会先想）")]
  static var system: String { appLang == "en" ? systemEn : systemZh }
  static let systemEn = [
    "You are the butler on the user's desktop. Answer in English, briefly and directly: conclusion first, then the reason.",
    "The user's information (quotes, holdings, calendar, mail, etc.) is attached before the question, possibly in Chinese. Answer only from it; if something isn't there, say so — never make things up.",
    "For stocks, give objective analysis only. Never recommend buying, selling, holding, adding or trimming.",
    "Only quote numbers exactly as given; do not convert or invent numbers.",
  ].joined(separator: "\n")
  static let systemZh = [
    "你是用户桌面上的管家。用简体中文回答，简短直接，先给结论再给理由。",
    "用户的信息（行情、持仓、日程、邮件等）会附在问题前面，只依据这些信息回答；没有的信息就说没有，不要编造。",
    "涉及股票只做客观分析，不给买入、卖出、持有、加仓、减仓的建议。",
    "数字只引用给你的原文，不要自己换算或编造。",
  ].joined(separator: "\n")
  static let maxHistory = 24    // 只带最近 24 条：对话越长越贵

  /** 流式回复要等模型想一会儿，不能用 10 秒就超时的那个会话 */
  static let session: URLSession = {
    let c = URLSessionConfiguration.ephemeral
    c.urlCache = nil
    c.timeoutIntervalForRequest = 120
    return URLSession(configuration: c)
  }()

  struct Failure: LocalizedError { let message: String; var errorDescription: String? { message } }

  static func explain(_ status: Int, _ body: String) -> String {
    let detail = ((try? JSONSerialization.jsonObject(with: Data(body.utf8))) as? JSON).flatMap { ($0["error"] as? JSON)?["message"] as? String } ?? ""
    switch status {
    case 401: return L("DeepSeek 的 API Key 不对或已失效：到「设置 → AI」里重新填一次")
    case 402: return L("DeepSeek 账户余额不足：去 platform.deepseek.com 充值后再试")
    case 429: return L("DeepSeek 请求太频繁，等几秒再试")
    case 500...: return L("DeepSeek 服务暂时不可用（%@），稍后再试", "\(status)")
    default: return L("DeepSeek 请求失败（%@）", "\(status)") + (detail.isEmpty ? "" : ": " + detail)
    }
  }

  private static func request(_ messages: [[String: String]], model: String, stream: Bool, maxTokens: Int? = nil) throws -> URLRequest {
    guard let key = Keychain.read() else { throw Failure(message: L("还没有设置 DeepSeek 的 API Key：到「设置 → AI」里粘贴（Key 只存在你这台电脑的钥匙串里）")) }
    var r = URLRequest(url: endpoint)
    r.httpMethod = "POST"
    r.setValue("application/json", forHTTPHeaderField: "Content-Type")
    r.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
    var body: JSON = ["model": model, "stream": stream, "messages": [["role": "system", "content": system]] + messages.suffix(maxHistory)]
    if let maxTokens { body["max_tokens"] = maxTokens }
    r.httpBody = try JSONSerialization.data(withJSONObject: body)
    return r
  }

  /** 流式：一段一段地回调。推理模型的「思考过程」不显示，只显示最终回答 */
  static func stream(_ messages: [[String: String]], model: String, onText: @escaping @MainActor (String) -> Void) async throws -> String {
    let (bytes, resp) = try await session.bytes(for: request(messages, model: model, stream: true))
    let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
    if status != 200 {
      var body = ""
      for try await line in bytes.lines { body += line; if body.count > 2000 { break } }
      throw Failure(message: explain(status, body))
    }
    var full = ""
    for try await line in bytes.lines {
      guard line.hasPrefix("data:") else { continue }
      let data = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
      if data == "[DONE]" { break }
      guard let j = (try? JSONSerialization.jsonObject(with: Data(data.utf8))) as? JSON,
            let piece = (((j["choices"] as? [JSON])?.first)?["delta"] as? JSON)?["content"] as? String, !piece.isEmpty else { continue }
      full += piece
      await onText(piece)
    }
    return full
  }

  /** 不要流式：一次拿到整段回复（后台判断重要邮件用） */
  static func complete(_ messages: [[String: String]], model: String) async throws -> String {
    let (d, resp) = try await session.data(for: request(messages, model: model, stream: false, maxTokens: 200))
    let st = (resp as? HTTPURLResponse)?.statusCode ?? 0
    guard st == 200 else { throw Failure(message: explain(st, String(decoding: d, as: UTF8.self))) }
    let j = (try? JSONSerialization.jsonObject(with: d)) as? JSON
    return (((j?["choices"] as? [JSON])?.first)?["message"] as? JSON)?["content"] as? String ?? ""
  }

  /** 设置页的「测试」 */
  static func test(model: String) async -> String? {
    do {
      let (d, resp) = try await session.data(for: request([["role": "user", "content": "你好"]], model: model, stream: false, maxTokens: 5))
      let st = (resp as? HTTPURLResponse)?.statusCode ?? 0
      return st == 200 ? nil : explain(st, String(decoding: d, as: UTF8.self))
    } catch { return L("连不上 DeepSeek：") + error.localizedDescription }
  }
}

// —— Claude Code 命令行 ——
enum ClaudeCLI {
  static var path: String? {
    let home = NSHomeDirectory()
    return [home + "/.local/bin/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude", home + "/.npm-global/bin/claude", home + "/.claude/local/claude"]
      .first { FileManager.default.isExecutableFile(atPath: $0) }
  }

  /** 从访达打开的 App 没有终端里的 PATH，补上常见位置 */
  static var env: [String: String] {
    var e = ProcessInfo.processInfo.environment
    let home = NSHomeDirectory()
    e["PATH"] = [home + "/.local/bin", "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin", e["PATH"] ?? ""].joined(separator: ":")
    return e
  }

  /** 跑一轮：每行输出解析成事件交给 onEvent；返回时进程已退出 */
  static func run(prompt: String, session: String?, cwd: String, permission: String, process: @escaping @MainActor (Process) -> Void,
                  onEvent: @escaping @MainActor (ClaudeEvent) -> Void) async {
    guard let exe = path else {
      await onEvent(.done(failed: true, text: L("没找到 Claude Code 命令行（claude）。装好 Claude Code 后再试，或换成 DeepSeek")))
      return
    }
    let p = Process()
    p.executableURL = URL(fileURLWithPath: exe)
    var args = ["-p", prompt, "--output-format", "stream-json", "--verbose", "--permission-mode", permission]
    if let session { args += ["--resume", session] }
    p.arguments = args
    p.currentDirectoryURL = URL(fileURLWithPath: cwd)
    p.environment = env
    let out = Pipe()
    p.standardOutput = out
    p.standardError = FileHandle.nullDevice
    p.standardInput = FileHandle.nullDevice
    do { try p.run() } catch {
      await onEvent(.done(failed: true, text: L("启动 Claude Code 失败：") + error.localizedDescription))
      return
    }
    await process(p)
    var sawDone = false
    do {
      for try await line in out.fileHandleForReading.bytes.lines {
        for e in ClaudeStream.parse(line) {
          if case .done = e { sawDone = true }
          await onEvent(e)
        }
      }
    } catch {}
    p.waitUntilExit()
    if !sawDone && p.terminationReason == .uncaughtSignal { await onEvent(.done(failed: false, text: "")) }
  }
}

// —— 一段对话（浮层 AI 条和总控台都用它） ——
struct PendingActions {
  var list: [ActionCheck]
  var withMail: Bool
  var results: [(ok: Bool, text: String)]? = nil
  var running = false
}

@MainActor
final class Chat: ObservableObject, Identifiable {
  let id = UUID()
  @Published var items: [TItem] = []
  @Published var busy = false
  @Published var pending: PendingActions?
  @Published var title = L("新对话")
  let agent: String                      // deepseek / claude
  var claudeSession: String?
  var cwd: String
  var permission = "default"             // Claude：default 只读（要改东西会被拒绝）/ acceptEdits 可以改文件
  private var history: [[String: String]] = []   // DeepSeek 的上下文
  private var task: Task<Void, Never>?
  private var proc: Process?
  var onFinish: ((String) -> Void)?      // 一轮结束：最后一句回答（AI 提醒用）

  init(agent: String, cwd: String = NSHomeDirectory(), claudeSession: String? = nil, items: [TItem] = []) {
    self.agent = agent
    self.cwd = cwd
    self.claudeSession = claudeSession
    self.items = items
    if let first = items.first(where: { $0.kind == .user }) { title = String(first.text.prefix(40)) }
  }

  var agentName: String { agent == "claude" ? "Claude Code" : "DeepSeek" }

  /** shown：显示在对话里的那句（用户自己打的字）；prompt：真正发出去的（可能拼了桌面上下文） */
  func send(shown: String, prompt: String, model: String = "deepseek-chat", parseActions: Bool = false, withMail: Bool = false) {
    guard !busy else { return }
    if items.isEmpty { title = String(shown.prefix(40)) }
    items.append(TItem(kind: .user, text: shown))
    busy = true
    pending = nil
    let start = items.count
    task = Task { [weak self] in
      guard let self else { return }
      if self.agent == "claude" {
        await ClaudeCLI.run(prompt: prompt, session: self.claudeSession, cwd: self.cwd, permission: self.permission,
                            process: { [weak self] p in self?.proc = p },
                            onEvent: { [weak self] e in
                              guard let self else { return }
                              if case .session(let s) = e { self.claudeSession = s }
                              ClaudeStream.apply(e, to: &self.items)
                            })
        self.proc = nil
      } else {
        self.history.append(["role": "user", "content": prompt])
        self.items.append(TItem(kind: .ai, text: ""))
        let at = self.items.count - 1
        do {
          let full = try await DeepSeek.stream(self.history, model: model) { [weak self] piece in
            guard let self, at < self.items.count else { return }
            self.items[at].text += piece
          }
          self.history.append(["role": "assistant", "content": full])
        } catch is CancellationError {
          self.items.append(TItem(kind: .notice, text: L("已停止")))
        } catch {
          self.history.removeLast()      // 这条没发成功，别留在历史里
          if (error as? URLError)?.code == .cancelled { self.items.append(TItem(kind: .notice, text: L("已停止"))) }
          else { self.items.append(TItem(kind: .error, text: error.localizedDescription)) }
        }
        if at < self.items.count, self.items[at].kind == .ai, self.items[at].text.isEmpty { self.items.remove(at: at) }
      }
      self.busy = false
      let answer = self.items[start...].filter { $0.kind == .ai }.map(\.text).joined(separator: "\n")
      if parseActions { self.detectActions(answer, withMail: withMail) }
      self.onFinish?(answer)
    }
  }

  func cancel() {
    task?.cancel()
    proc?.terminate()
  }

  /** 这一问的回复结束了：有 actions 块就生成确认卡（校验过的才会出现在卡上，不认识的标明「不执行」） */
  private func detectActions(_ answer: String, withMail: Bool) {
    guard answer.contains("```actions") else { return }
    let r = Actions.extract(answer)
    if let raw = r.raw { pending = PendingActions(list: Actions.checkAll(raw), withMail: withMail) }
    else if let e = r.error { items.append(TItem(kind: .notice, text: e + L("，没有执行任何操作"))) }
  }

  /** 显示用的文字：actions 块不给人看（流式输出到一半也先藏起来） */
  static func display(_ t: TItem) -> String { t.kind == .ai && t.text.contains("```actions") ? Actions.extract(t.text).text : t.text }
}

// —— 管家需要的上下文文字、办事、提醒、邮件概括 ——
extension DeskModel {
  static let ctxKinds = [("market", "行情"), ("quant", "量化账户"), ("plans", "自选计划"), ("calendar", "日程"), ("mail", "邮件")]
  static let ctxShort = ["market": "行情", "quant": "量化", "plans": "计划", "calendar": "日程", "mail": "邮件"]

  var aiAgent: String { store.data["aiAgent"] as? String == "claude" ? "claude" : "deepseek" }
  var reminderAgent: String { store.data["reminderAgent"] as? String == "claude" ? "claude" : "deepseek" }
  var deepseekModel: String { DeepSeek.models.map(\.0).contains(store.data["deepseekModel"] as? String ?? "") ? store.data["deepseekModel"] as! String : "deepseek-chat" }
  var nlActions: Bool { store.data["nlActions"] as? Bool != false }

  func marketText() -> String {
    let qs = store.watch.compactMap { quotes[$0] }.filter { !$0.failed }
    if qs.isEmpty { return "（暂无行情）" }
    return qs.map { q in
      let t = q.ts.map { ms -> String in let x = ymd(ms); return "\(x.y)/\(x.m)/\(x.d) \(pad2(x.h)):\(pad2(x.mi))" } ?? "未知"
      return "\(q.name)（\(q.code)）\(q.price.map(jsNum) ?? "—")，\((q.pct ?? 0) >= 0 ? "+" : "")\(q.pct.map(jsNum) ?? "—")%，\(q.status == "live" ? "交易中" : "已收盘")，数据时间 \(t)"
    }.joined(separator: "\n")
  }

  func calendarText() -> String {
    guard let c = calendar, c.ok else { return "（读不到日历：\(calendar?.error ?? "还没加载")）" }
    let now = nowMs()
    let soon = c.events.filter { $0.end > now && $0.start < now + 3 * 86400e3 }
    if soon.isEmpty { return "（今天起三天内没有日程）" }
    return soon.prefix(20).map { e in
      let d = ymd(e.start)
      return "\(d.m)/\(d.d) \(F.week[d.wd]) \(e.allDay ? "全天" : F.hm(e.start) + "–" + F.hm(e.end)) \(e.title)\(e.location.isEmpty ? "" : "（\(e.location)）")"
    }.joined(separator: "\n")
  }

  func mailText() -> String {
    guard let m = mail, m.ok else { return "（读不到邮件：\(mail?.error ?? "还没加载")）" }
    if m.items.isEmpty { return "（没有未读邮件）" }
    return "共 \(m.unread) 封未读，最近几封：\n" + m.items.map { "\($0.name)：\($0.subject)" }.joined(separator: "\n")
  }

  func plansText() -> String {
    let plans = store.plans
    let lines = store.watch.map { k -> String in
      let q = quotes[k]
      let p = Plans.norm(plans[k])
      var bits: [String] = []
      if let b = p.buy { bits.append("买入价 \(jsNum(b))") }
      if let s = p.sell { bits.append("卖出价 \(jsNum(s))") }
      if !p.note.isEmpty { bits.append("观察：\(p.note)") }
      return "\(q?.name ?? k)（\(q?.code ?? k)）\(q?.price.map { "现价 " + jsNum($0) } ?? "没有现价")，\(bits.isEmpty ? "没设计划" : bits.joined(separator: "，"))"
    }
    let acct = store.acctSize
    let head = acct > 0 ? "我的账户金额 \(jsNum(acct))，单票上限 \(jsNum(store.maxPerPct))%（都是我自己填的参考值，不是量化系统的数字）" : "我还没在桌面端填账户金额"
    return head + "\n" + (lines.isEmpty ? "（自选是空的）" : lines.joined(separator: "\n"))
  }

  func quantText() -> String {
    guard let q = quant, q.ok else { return "（读不到量化系统）" }
    let p = q.positions.map { "\($0.name) \($0.shares.map(jsNum) ?? "—") 股，成本 \($0.cost.map(jsNum) ?? "—")，现价 \($0.price.map(jsNum) ?? "—")，浮动盈亏 \($0.pnlPct.map(jsNum) ?? "—")%" }.joined(separator: "；")
    return "总资产 \(q.account?.total.map(jsNum) ?? "—")，相对初始资金 \(q.account?.pnlPct.map(jsNum) ?? "—")%；持仓：\(p.isEmpty ? "无" : p)；风控状态：\(q.risk?.status ?? "—")（回撤 \(q.risk?.drawdown.map(jsNum) ?? "—")%）；数据时间 \(q.updatedAt ?? "—")\(q.running == true ? "" : "（量化系统已停机，数据不是最新）")"
  }

  func ctxText(_ k: String) -> String {
    switch k {
    case "market": return marketText()
    case "quant": return quantText()
    case "plans": return plansText()
    case "calendar": return calendarText()
    case "mail": return mailText()
    default: return ""
    }
  }

  /** 普通提问：桌面上的信息拼在问题前面（默认全带：管家「知道所有信息」靠的就是这一步）+ 能力说明 */
  func buildPrompt(_ text: String, ctx: Set<String>) -> (prompt: String, allowActions: Bool) {
    let parts = DeskModel.ctxKinds.filter { ctx.contains($0.0) }.map { "【\($0.1)】\n" + ctxText($0.0) }
    let allow = nlActions
    let block = parts.isEmpty ? "" : "下面是我电脑桌面上的信息，供你参考（行情是延迟数据；涉及股票时只做客观分析，不要给买入、卖出、持有建议）：\n\n" + parts.joined(separator: "\n\n") + "\n\n"
    let spec = allow ? Actions.spec + "\n\n" : ""
    let lang = appLang == "en" ? "（请用英文回答 / Please answer in English.）\n" : ""
    return (block.isEmpty && spec.isEmpty ? lang + text : "\(block)\(spec)\(lang)我的问题：\(text)", allow)
  }

  // —— 办事 ——
  /** 代码、别名或名称 → 一条确认能拿到行情的品种 */
  func resolveSymbol(_ input: String) async throws -> Quote {
    var key = Market.toSinaKey(input)
    if key == nil, let d = try? await Fetch.get(SymbolSearch.url(input), headers: ["Referer": "https://finance.sina.com.cn"], timeout: 8) {
      let gbk = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))
      key = SymbolSearch.pick(String(data: d, encoding: String.Encoding(rawValue: gbk)) ?? "", query: input)
    }
    guard let key else { throw Fetch.HTTPError(message: L("认不出「%@」。A 股填 6 位数字，港股填 5 位数字，美股填字母代码，或者写全称", input)) }
    guard let q = try await Fetch.quotes([key])[key], !q.failed else { throw Fetch.HTTPError(message: L("没查到「%@」的行情", input)) }
    return q
  }

  func addWatch(_ q: Quote) -> String {
    if store.watch.contains(q.key) { return L("「%@」已经在自选里了", q.name) }
    quotes[q.key] = q
    store.set(["watch": store.watch + [q.key]])
    return L("已加入自选：%@", q.name)
  }

  func runActions(_ list: [Action], chat: Chat?) async -> [(ok: Bool, text: String)] {
    var out: [(Bool, String)] = []
    for a in list {
      switch a.kind {
      case "watch.add":
        do { out.append((true, addWatch(try await resolveSymbol(a.p["query"]!)))) } catch { out.append((false, error.localizedDescription)) }
      case "nav": page = a.p["page"]!; out.append((true, L("已切换页面")))
      case "refresh": kick(a.p["what"]!); out.append((true, L("已刷新")))
      case "mail.digest": await digestMail(into: chat); out.append((true, L("已开始概括邮件，结果在上面的对话里")))
      case "open.url": openURL(a.p["url"]!); out.append((true, L("已在浏览器里打开")))
      default:
        let r = Actions.storePatch(a, store: store.data, quotes: quotes)
        if let patch = r.patch { store.set(patch); out.append((true, r.note ?? L("已完成"))) } else { out.append((false, r.error ?? L("做不了"))) }
      }
    }
    return out
  }

  // —— 邮件正文与概括（只有你点开某一封、或让管家概括时才读正文；正文会发给你选的 AI） ——
  static let askOne = "请概括下面这封邮件：它想让我做什么、有没有截止时间、重要吗（一句话理由）。简短，先给结论。"
  static let askMany = "下面是我最近几封邮件的正文。请逐封用一句话概括，并标出：需不需要我回复、有没有截止时间；最后告诉我最该先处理哪一封。简短，不要复述原文。"

  static func mailPrompt(_ name: String, _ email: String, _ subject: String, _ body: String) -> String {
    "发件人：\(name)\(email.isEmpty ? "" : " <\(email)>")\n主题：\(subject)\n正文：\n\(body.isEmpty ? "（没有正文）" : body)"
  }

  /** 挑「有人在等你 / 钱和账户」的邮件（没有就取最近几封），读正文，一次交给 AI。带着别人写的正文的提问不附能力说明、不解析 actions */
  func digestMail(into chat: Chat?, max: Int = 5) async {
    guard let m = mail, m.ok, !m.items.isEmpty else { toast = L("没有读到未读邮件"); return }
    let important = Set(Cands.mail(m.items, rules: mailRulesNow).map { String($0.id.dropFirst(5)) })
    var picks = m.items.filter { important.contains($0.id) }.prefix(max).map { $0 }
    let fallback = picks.isEmpty
    if fallback { picks = Array(m.items.prefix(max)) }
    toast = L(fallback ? "正在读取 %@ 封最近的邮件的正文…" : "正在读取 %@ 封重要邮件的正文…", "\(picks.count)")
    var bodies: [String] = []
    for x in picks {
      if case .ok(let name, let email, let subject, let body) = await mailBody(x.id, maxChars: 1500) {
        bodies.append(DeskModel.mailPrompt(name.isEmpty ? x.name : name, email, subject.isEmpty ? x.subject : subject, body))
      }
    }
    guard !bodies.isEmpty else { toast = L("邮件正文读取失败（「邮件」App 要开着）"); return }
    let text = DeskModel.askMany + (fallback ? "（没有命中「重要」规则，这是最近的几封。）" : "") + "\n\n" + bodies.enumerated().map { "【\($0.offset + 1)】\n\($0.element)" }.joined(separator: "\n\n———\n\n")
    let c = chat ?? overlayChat
    c.send(shown: L(fallback ? "概括 %@ 封最近的邮件" : "概括 %@ 封重要邮件", "\(bodies.count)"), prompt: text + (appLang == "en" ? "\n\nPlease answer in English." : ""), model: deepseekModel)
    toast = nil
  }

  // —— AI 提醒：到点在后台跑，结果发通知、写在提醒卡上 ——
  func checkReminders() {
    for r in Reminders.due(store.data["reminders"] as? [JSON] ?? []) { if let id = r["id"] as? String { runReminder(id) } }
  }

  func patchReminder(_ id: String, _ patch: JSON) {
    let list = (store.data["reminders"] as? [JSON] ?? []).map { r -> JSON in
      guard r["id"] as? String == id else { return r }
      var x = r
      for (k, v) in patch { x[k] = v }
      return x
    }
    store.set(["reminders": list])
  }

  func runReminder(_ id: String) {
    guard !runningReminders.contains(id), let r = (store.data["reminders"] as? [JSON])?.first(where: { $0["id"] as? String == id }) else { return }
    runningReminders.insert(id)
    patchReminder(id, ["lastRunDay": Reminders.dayKey(nowMs()), "running": true, "lastError": NSNull()])
    let title = (r["title"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? L("提醒")
    let prompt = (r["prompt"] as? String ?? "").trimmed()
    Task { @MainActor in
      defer { self.runningReminders.remove(id) }
      if prompt.isEmpty {
        self.patchReminder(id, ["running": false, "lastResult": NSNull(), "lastRunAt": nowMs()])
        self.notify(title, L("时间到了"))
        return
      }
      let c = r["context"] as? JSON ?? [:]
      let on = { (k: String) in (c[k] as? Bool) == true }
      if on("mail") { await self.refreshMail() }
      let p = Reminders.buildPrompt(r, calendar: on("calendar") ? self.calendarText() : nil, mail: on("mail") ? self.mailText() : nil,
                                    market: on("market") ? self.marketText() : nil, quant: on("quant") ? self.quantText() : nil)
      let chat = Chat(agent: self.reminderAgent)
      let answer: String = await withCheckedContinuation { cont in
        chat.onFinish = { cont.resume(returning: $0) }
        chat.send(shown: title, prompt: p, model: self.deepseekModel)
      }
      if let err = chat.items.last(where: { $0.kind == .error }) {
        self.patchReminder(id, ["running": false, "lastError": err.text, "lastRunAt": nowMs()])
        self.notify(title + L("（AI 没有回复）"), err.text)
      } else {
        let text = answer.trimmed()
        self.patchReminder(id, ["running": false, "lastResult": text.isEmpty ? NSNull() : text, "lastRunAt": nowMs()])
        self.notify(title, Reminders.notifyBody(text).isEmpty ? title : Reminders.notifyBody(text))
      }
    }
  }
}
