// 对话记录（浮层 AI 条和总控台共用）+ Claude Code 命令行输出的解析 + 本机 Claude 会话的读取。
//
// Claude Code 不再走 ACP（那要一个 Node 写的适配器常驻）：直接用命令行自带的
//   claude -p "<问题>" --output-format stream-json --verbose [--resume <会话>]
// 每问一次起一个进程，答完就退出，闲着时一点内存都不占。会话记录本来就存在 ~/.claude/projects 里，读出来就能接着聊。
import Foundation

struct TItem: Identifiable, Equatable {
  enum Kind: Equatable { case user, ai, tool, notice, error }
  let id = UUID()
  var kind: Kind
  var text: String
  var detail = ""          // 工具：参数摘要 / 结果
  var toolId = ""
  var failed = false
}

/** Claude 命令行的一行输出 → 要做的事 */
enum ClaudeEvent: Equatable {
  case session(String)
  case text(String)
  case tool(id: String, title: String, detail: String)
  case toolResult(id: String, failed: Bool, text: String)
  case done(failed: Bool, text: String)
}

enum ClaudeStream {
  /** 工具调用的一行摘要：读哪个文件、跑什么命令 */
  static func toolTitle(_ name: String, _ input: JSON) -> (String, String) {
    let pick = ["file_path", "command", "pattern", "url", "path", "query", "description", "prompt"].lazy.compactMap { input[$0] as? String }.first ?? ""
    let short = pick.count > 120 ? String(pick.prefix(120)) + "…" : pick
    let names = ["Read": "读文件", "Write": "写文件", "Edit": "改文件", "Bash": "运行命令", "Grep": "搜索", "Glob": "找文件", "WebFetch": "读网页", "WebSearch": "搜网页", "Task": "子任务", "TodoWrite": "任务清单"]
    return (names[name] ?? name, short)
  }

  private static func resultText(_ c: Any?) -> String {
    if let s = c as? String { return s }
    if let a = c as? [JSON] { return a.compactMap { $0["text"] as? String }.joined(separator: "\n") }
    return ""
  }

  static func parse(_ line: String) -> [ClaudeEvent] {
    guard let d = line.data(using: .utf8), let j = (try? JSONSerialization.jsonObject(with: d)) as? JSON else { return [] }
    switch j["type"] as? String {
    case "system":
      if j["subtype"] as? String == "init", let s = j["session_id"] as? String { return [.session(s)] }
    case "assistant":
      let blocks = (j["message"] as? JSON)?["content"] as? [JSON] ?? []
      return blocks.compactMap { b in
        switch b["type"] as? String {
        case "text": return (b["text"] as? String).map { .text($0) }
        case "tool_use":
          let (t, detail) = toolTitle(b["name"] as? String ?? "", b["input"] as? JSON ?? [:])
          return .tool(id: b["id"] as? String ?? "", title: t, detail: detail)
        default: return nil
        }
      }
    case "user":
      let blocks = (j["message"] as? JSON)?["content"] as? [JSON] ?? []
      return blocks.compactMap { b in
        guard b["type"] as? String == "tool_result" else { return nil }
        return .toolResult(id: b["tool_use_id"] as? String ?? "", failed: (b["is_error"] as? Bool) == true, text: String(resultText(b["content"]).prefix(400)))
      }
    case "result":
      let failed = (j["is_error"] as? Bool) == true || (j["subtype"] as? String ?? "success") != "success"
      return [.done(failed: failed, text: j["result"] as? String ?? "")]
    default: break
    }
    return []
  }

  /** 把事件叠进对话记录（工具结果合并到对应那条工具上） */
  static func apply(_ e: ClaudeEvent, to items: inout [TItem]) {
    switch e {
    case .session: break
    case .text(let t):
      if !t.isEmpty { items.append(TItem(kind: .ai, text: t)) }
    case .tool(let id, let title, let detail):
      items.append(TItem(kind: .tool, text: title, detail: detail, toolId: id))
    case .toolResult(let id, let failed, let text):
      if let i = items.lastIndex(where: { $0.kind == .tool && $0.toolId == id }) {
        items[i].failed = failed
        if failed { items[i].detail += "\n" + text }
      }
    case .done(let failed, let text):
      if failed { items.append(TItem(kind: .error, text: explain(text))) }
    }
  }

  /** 命令行的报错翻译成人话 */
  static func explain(_ text: String) -> String {
    if text.test("not logged in|/login|auth", .caseInsensitive) { return L("Claude Code 命令行还没登录：在终端运行 claude，按提示登录后再试（或换成 DeepSeek）") }
    if text.test("credit|billing|quota", .caseInsensitive) { return L("Claude 额度不够了：") + text }
    return text.isEmpty ? L("Claude Code 出错了") : text
  }
}

// —— 本机的 Claude 会话（~/.claude/projects/<目录>/<会话id>.jsonl） ——
struct ClaudeSessionInfo: Identifiable, Equatable {
  var id: String
  var title: String
  var cwd: String
  var updated: Double
  var file: String
}

enum ClaudeSessions {
  static var root: String { NSHomeDirectory() + "/.claude/projects" }

  /** 一行记录里用户说的话（命令、系统注入的那种不算） */
  static func userText(_ j: JSON) -> String? {
    guard j["type"] as? String == "user", (j["isMeta"] as? Bool) != true, let m = j["message"] as? JSON else { return nil }
    var text = ""
    if let s = m["content"] as? String { text = s }
    else if let a = m["content"] as? [JSON] {
      if a.contains(where: { $0["type"] as? String == "tool_result" }) { return nil }
      text = a.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }.joined(separator: "\n")
    }
    let t = text.trimmed()
    if t.isEmpty || t.hasPrefix("<") || t.hasPrefix("Caveat:") { return nil }
    return t
  }

  /** 读文件头几十行：会话在哪个目录、第一句问了什么 */
  static func info(_ path: String) -> ClaudeSessionInfo? {
    guard let fh = FileHandle(forReadingAtPath: path) else { return nil }
    defer { try? fh.close() }
    let head = String(decoding: fh.readData(ofLength: 96 * 1024), as: UTF8.self)
    var cwd = "", title = ""
    for line in head.split(separator: "\n").prefix(80) {
      guard let j = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? JSON else { continue }
      if cwd.isEmpty, let c = j["cwd"] as? String { cwd = c }
      if title.isEmpty, let t = userText(j) { title = t.replace("\\s+", " ") }
      if !cwd.isEmpty && !title.isEmpty { break }
    }
    guard !title.isEmpty else { return nil }
    let id = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
    let mtime = ((try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
    return ClaudeSessionInfo(id: id, title: title.count > 60 ? String(title.prefix(60)) + "…" : title, cwd: cwd, updated: mtime * 1000, file: path)
  }

  /** 最近的会话（按修改时间，最多 limit 条） */
  static func list(limit: Int = 40) -> [ClaudeSessionInfo] {
    let fm = FileManager.default
    var files: [(String, Date)] = []
    for dir in (try? fm.contentsOfDirectory(atPath: root)) ?? [] {
      let d = root + "/" + dir
      for f in (try? fm.contentsOfDirectory(atPath: d)) ?? [] where f.hasSuffix(".jsonl") {
        let p = d + "/" + f
        if let m = (try? fm.attributesOfItem(atPath: p))?[.modificationDate] as? Date { files.append((p, m)) }
      }
    }
    return files.sorted { $0.1 > $1.1 }.prefix(limit * 2).compactMap { info($0.0) }.prefix(limit).map { $0 }
  }

  /** 整段历史 → 对话记录（只留最后 maxItems 条，长会话不至于吃内存） */
  static func history(_ path: String, maxItems: Int = 200) -> [TItem] {
    guard let data = FileManager.default.contents(atPath: path) else { return [] }
    var items: [TItem] = []
    for line in String(decoding: data, as: UTF8.self).split(separator: "\n") {
      guard let j = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? JSON else { continue }
      if let t = userText(j) { items.append(TItem(kind: .user, text: t)); continue }
      if (j["isSidechain"] as? Bool) == true { continue }
      if j["type"] as? String == "assistant" || j["type"] as? String == "user" {
        for e in ClaudeStream.parse(String(line)) { ClaudeStream.apply(e, to: &items) }
      }
    }
    return Array(items.suffix(maxItems))
  }
}
