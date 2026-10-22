// 自然语言办事（从 Electron 版 src/main/desk/actions.js 原样移植，安全边界一条不放宽）：
// 你对管家说「把腾讯加进自选」「明早 8 点提醒我交作业」，它回一段话 + 一个 actions 代码块，
// 这里解析、逐字段校验，生成确认卡上的说明；你点了「执行」才真的去做。
//
//   · 只能做「这个软件内部」的低风险操作：自选、你自己填的计划价、提醒、页面、组件、几个外观设置、刷新、概括邮件、打开 https 链接
//   · 绝不碰：下单 / 买卖建议、发送·回复·删除邮件、改日历、改量化系统、删文件。白名单之外一律拒绝
//   · 永远先确认再执行，没有「自动执行」
//   · 确认卡上的每一行都是这里根据校验后的参数自己生成的，模型写的说明文字不作数（它没法把「删除」说成「查看」）
//   · 附带了邮件正文的那种问答（概括邮件）不解析 actions：邮件是别人写的，可能夹带指令
import Foundation

struct Action: Equatable {
  var kind: String              // do 字段
  var p: [String: String] = [:] // 校验过的参数（都转成文字存，数字用 jsNum）
  var days: [Int] = []          // reminder.add 专用
  var enabled: Bool?            // reminder.toggle 专用
  func num(_ k: String) -> Double? { p[k].flatMap(Double.init) }
}

struct ActionCheck: Equatable {
  var action: Action?
  var error: String?
  var ok: Bool { action != nil }
}

enum Actions {
  static let maxActions = 6
  static let pages = ["home", "butler", "market", "news", "settings"]
  static let pageName = ["home": "主页", "butler": "管家", "market": "市场", "news": "新闻", "settings": "设置"]
  static let settings: [String: (values: [String]?, text: Int?, label: String, show: [String: String])] = [
    "colors": (["mono", "rup", "gup"], nil, "涨跌颜色", ["mono": "中性（▲ ▼）", "rup": "红涨绿跌", "gup": "绿涨红跌"]),
    "butlerName": (nil, 20, "管家的名字", [:]),
    "aiAgent": (["deepseek", "claude"], nil, "桌面 AI", ["deepseek": "DeepSeek", "claude": "Claude Code"]),
    "deepseekModel": (["deepseek-chat", "deepseek-reasoner"], nil, "DeepSeek 模型", ["deepseek-chat": "对话", "deepseek-reasoner": "推理"]),
  ]
  static let refreshable = ["news", "market", "mail", "weather", "calendar"]
  /** 要联网 / 要界面配合才能做的动作，由执行器处理；其余的都能直接算出对设置的修改（storePatch） */
  static let asyncActions: Set<String> = ["watch.add", "nav", "refresh", "mail.digest", "open.url"]

  /** 给模型看的「你能做什么」。每次正常提问都会附在问题前面（概括邮件那种不附） */
  static var spec: String {
    [
      "【你可以帮我操作这个桌面软件】",
      "只有当我明确要求你「去做某件事」时，才在回答最后附一个 actions 代码块（先用一句话说你打算做什么）；只是提问、聊天、分析时不要输出。格式：",
      "```actions",
      "[{\"do\":\"watch.add\",\"query\":\"腾讯\"}]",
      "```",
      "可用的 do（一次最多 \(maxActions) 个；没有列出的事情你做不到，请直接告诉我）：",
      "- watch.add {query}：把某个品种加入自选（名称或代码）；watch.remove {query}：从自选移除",
      "- plan.set {query, buy?, sell?, note?}：记下我自己填的买入价 / 卖出价 / 观察（数字必须是我说的，你不要替我定）",
      "- alert.price {query, above?, below?}：价格到达提醒；alert.pct {value}：涨跌幅超过多少 % 时通知（0 = 关闭）",
      "- reminder.add {title, time:\"HH:MM\", days?:\"daily\"|\"weekdays\"|\"weekends\"|[1-7], prompt?}：新建提醒（prompt 是到点让 AI 做什么，可空）",
      "- reminder.remove {title}；reminder.toggle {title, enabled:true|false}",
      "- nav {page:\"\(pages.joined(separator: "|"))\"}：切到某一页",
      "- widget.show {id} / widget.hide {id}：显示 / 收起桌面组件，id 是 \(WIDGETS.map(\.id).joined(separator: "|"))；widget.size {id, size:\"S|M|L|T|W|XL\"}：换大小",
      "- setting {key:\"colors|butlerName|aiAgent|deepseekModel\", value}：改外观 / 名字 / 用哪个 AI",
      "- refresh {what:\"\(refreshable.joined(separator: "|"))\"}：刷新数据；mail.digest {}：读几封重要邮件的正文并概括；open.url {url:\"https://…\"}：打开网页",
      "我会先看到确认卡，点了才执行。你不能、也不要：下单、给买入卖出持有的建议、发送 / 回复 / 删除邮件、改日历、改量化系统。",
    ].joined(separator: "\n")
  }

  // —— 从回复里取出 actions 块 ——
  /** 回复 → (给人看的文字, 解析出来的数组, 错误)。流式输出到一半（块还没闭合）也把已经出现的那部分藏起来 */
  static func extract(_ reply: String) -> (text: String, raw: [Any]?, error: String?) {
    guard let m = reply.match("```actions[ \\t]*\\r?\\n([\\s\\S]*?)```") else {
      let text = reply.range(of: "```actions").map { String(reply[..<$0.lowerBound]) } ?? reply
      return (text.trimmingTrailing(), nil, nil)
    }
    let whole = m[0]!
    let r = reply.range(of: whole)!
    // 只认第一块；后面再出现的 actions 块一律丢掉（别让一次回复偷偷带两批）
    let text = (String(reply[..<r.lowerBound]) + String(reply[r.upperBound...])).replace("```actions[\\s\\S]*?(```|$)", "").trimmingTrailing()
    guard let data = m[1]?.trimmed().data(using: .utf8), let any = try? JSONSerialization.jsonObject(with: data) else {
      return (text, nil, "没能看懂模型给的操作列表（格式不对）")
    }
    guard let arr = any as? [Any] else { return (text, nil, "actions 不是数组") }
    return (text, arr, nil)
  }

  // —— 校验 ——
  private static func s(_ v: Any?, _ max: Int) -> String? {
    guard let t = (v as? String)?.trimmed(), !t.isEmpty, t.count <= max else { return nil }
    return t
  }
  private static func n(_ v: Any?) -> Double? {
    if let b = v as? NSNumber, CFGetTypeID(b) == CFBooleanGetTypeID() { return nil }
    if let d = v as? NSNumber { return d.doubleValue.isFinite ? d.doubleValue : nil }
    if let t = (v as? String)?.trimmed(), !t.isEmpty, let d = Double(t), d.isFinite { return d }
    return nil
  }
  private static func pos(_ v: Any?) -> Double? { n(v).flatMap { $0 > 0 && $0 < 1e9 ? $0 : nil } }

  static func normTime(_ v: Any?) -> String? {
    guard let m = ((v as? String) ?? "").trimmed().match("^(\\d{1,2})[:：](\\d{2})$"), let h = Int(m[1]!), let mi = Int(m[2]!), h <= 23, mi <= 59 else { return nil }
    return "\(pad2(h)):\(m[2]!)"
  }

  /** 空 = 每天；工作日 1–5；周末 6、7；nil = 写错了 */
  static func normDays(_ v: Any?) -> [Int]? {
    if v == nil || v is NSNull { return [] }
    if let t = v as? String {
      switch t {
      case "daily", "每天": return []
      case "weekdays", "工作日": return [1, 2, 3, 4, 5]
      case "weekends", "周末": return [6, 7]
      default: return nil
      }
    }
    if let a = v as? [Any] {
      if a.isEmpty { return [] }
      let d = Set(a.compactMap { n($0) }.filter { $0 == $0.rounded() && $0 >= 1 && $0 <= 7 }.map { Int($0) }).sorted()
      return d.isEmpty ? nil : d
    }
    return nil
  }

  static func check(_ raw: Any?) -> ActionCheck {
    guard let o = raw as? JSON else { return ActionCheck(error: "不是一个操作") }
    let d = o["do"] as? String ?? ""
    func bad(_ e: String) -> ActionCheck { ActionCheck(error: e) }
    func ok(_ p: [String: String], days: [Int] = [], enabled: Bool? = nil) -> ActionCheck { ActionCheck(action: Action(kind: d, p: p, days: days, enabled: enabled)) }
    switch d {
    case "watch.add", "watch.remove":
      guard let q = s(o["query"], 40) else { return bad("缺少要操作的品种名称或代码") }
      return ok(["query": q])
    case "plan.set":
      guard let q = s(o["query"], 40) else { return bad("缺少品种") }
      let buy = o["buy"] == nil ? nil : pos(o["buy"]), sell = o["sell"] == nil ? nil : pos(o["sell"])
      if o["buy"] != nil && buy == nil { return bad("买入价不是有效的数字") }
      if o["sell"] != nil && sell == nil { return bad("卖出价不是有效的数字") }
      let note = (o["note"] as? String).map { String($0.trimmed().prefix(80)) }
      if o["note"] != nil && note == nil { return bad("观察不是文字") }
      if buy == nil && sell == nil && note == nil { return bad("没有要记的内容（买入价、卖出价、观察至少一个）") }
      var p = ["query": q]
      if let buy { p["buy"] = jsNum(buy) }
      if let sell { p["sell"] = jsNum(sell) }
      if let note { p["note"] = note }
      return ok(p)
    case "alert.price":
      guard let q = s(o["query"], 40) else { return bad("缺少品种") }
      let above = o["above"] == nil ? nil : pos(o["above"]), below = o["below"] == nil ? nil : pos(o["below"])
      if (o["above"] != nil && above == nil) || (o["below"] != nil && below == nil) { return bad("价格不是有效的数字") }
      if above == nil && below == nil { return bad("高于 / 低于至少填一个") }
      var p = ["query": q]
      if let above { p["above"] = jsNum(above) }
      if let below { p["below"] = jsNum(below) }
      return ok(p)
    case "alert.pct":
      guard let v = n(o["value"]), v >= 0, v <= 20 else { return bad("涨跌幅阈值要在 0–20 之间") }
      return ok(["value": jsNum(v)])
    case "reminder.add":
      guard let title = s(o["title"], 40) else { return bad("提醒缺少标题") }
      guard let time = normTime(o["time"]) else { return bad("提醒时间要写成 HH:MM") }
      guard let days = normDays(o["days"]) else { return bad("提醒的星期不对") }
      var prompt = ""
      if let pr = o["prompt"], !(pr is NSNull) {
        guard let t = pr as? String else { return bad("提醒的 AI 指令不对") }
        prompt = String(t.trimmed().prefix(300))
      }
      return ok(["title": title, "time": time, "prompt": prompt], days: days)
    case "reminder.remove":
      guard let t = s(o["title"], 40) else { return bad("缺少提醒标题") }
      return ok(["title": t])
    case "reminder.toggle":
      guard let t = s(o["title"], 40), let e = o["enabled"] as? NSNumber, CFGetTypeID(e) == CFBooleanGetTypeID() else { return bad("缺少提醒标题或 enabled") }
      return ok(["title": t], enabled: e.boolValue)
    case "nav":
      guard let p = o["page"] as? String, pages.contains(p) else { return bad("没有这一页") }
      return ok(["page": p])
    case "widget.show", "widget.hide":
      guard let id = o["id"] as? String, widgetDef(id) != nil else { return bad("没有这个组件") }
      return ok(["id": id])
    case "widget.size":
      guard let id = o["id"] as? String, let def = widgetDef(id) else { return bad("没有这个组件") }
      guard let size = o["size"] as? String, def.sizes.contains(size) else { return bad("「\(def.label)」没有这个大小（可选：\(def.sizes.joined(separator: " / "))）") }
      return ok(["id": id, "size": size])
    case "setting":
      guard let key = o["key"] as? String, let spec = settings[key] else { return bad("这个设置不能由管家来改") }
      if let values = spec.values {
        guard let v = o["value"] as? String, values.contains(v) else { return bad("「\(spec.label)」不能设成这个值") }
        return ok(["key": key, "value": v])
      }
      guard let v = s(o["value"], spec.text ?? 20) else { return bad("「\(spec.label)」不能为空，最多 \(spec.text ?? 20) 个字") }
      return ok(["key": key, "value": v])
    case "refresh":
      guard let w = o["what"] as? String, refreshable.contains(w) else { return bad("不能刷新这个") }
      return ok(["what": w])
    case "mail.digest":
      return ok([:])
    case "open.url":
      guard let u = s(o["url"], 300), URL(string: u)?.scheme == "https", URL(string: u)?.host != nil else { return bad("只能打开 https 链接") }
      return ok(["url": u])
    default:
      return bad("不支持这个操作")
    }
  }

  /** 一批：最多 6 个，每个都校验；多出来的写一行说明 */
  static func checkAll(_ raw: [Any]?) -> [ActionCheck] {
    let list = raw ?? []
    var out = list.prefix(maxActions).map(check)
    if list.count > maxActions { out.append(ActionCheck(error: "一次最多 \(maxActions) 件，多出来的 \(list.count - maxActions) 件没有列出")) }
    return out
  }

  // —— 确认卡上的说明：全部由这里根据校验后的参数生成 ——
  private static let dayName = ["", "周一", "周二", "周三", "周四", "周五", "周六", "周日"]
  static func daysText(_ d: [Int]) -> String {
    if d.isEmpty { return "每天" }
    if d == [1, 2, 3, 4, 5] { return "工作日" }
    if d == [6, 7] { return "周末" }
    return d.map { dayName[$0] }.joined(separator: "、")
  }

  static func describe(_ a: Action) -> String {
    let p = a.p
    switch a.kind {
    case "watch.add": return "把「\(p["query"]!)」加入自选"
    case "watch.remove": return "把「\(p["query"]!)」从自选移除"
    case "plan.set":
      let bits = [p["buy"].map { "买入价 \($0)" }, p["sell"].map { "卖出价 \($0)" }, p["note"].map { "观察「\($0)」" }].compactMap { $0 }
      return "给「\(p["query"]!)」记下：\(bits.joined(separator: "、"))（只是记下，不会下单）"
    case "alert.price":
      let bits = [p["above"].map { "高于 \($0)" }, p["below"].map { "低于 \($0)" }].compactMap { $0 }
      return "「\(p["query"]!)」\(bits.joined(separator: "、"))时提醒我"
    case "alert.pct": return p["value"] == "0" ? "关闭涨跌幅通知" : "涨跌幅超过 \(p["value"]!)% 时通知我"
    case "reminder.add":
      let pr = p["prompt"] ?? ""
      return "新建提醒：\(daysText(a.days)) \(p["time"]!)「\(p["title"]!)」" + (pr.isEmpty ? "" : "（到点让 AI：\(pr.prefix(40))\(pr.count > 40 ? "…" : "")）")
    case "reminder.remove": return "删除提醒「\(p["title"]!)」"
    case "reminder.toggle": return "\(a.enabled == true ? "开启" : "关闭")提醒「\(p["title"]!)」"
    case "nav": return "切到「\(pageName[p["page"]!] ?? "")」页"
    case "widget.show": return "在桌面上显示「\(widgetDef(p["id"]!)!.label)」"
    case "widget.hide": return "把「\(widgetDef(p["id"]!)!.label)」从桌面上收起"
    case "widget.size": return "把「\(widgetDef(p["id"]!)!.label)」换成「\(SIZES[p["size"]!]?.label ?? p["size"]!)」档大小"
    case "setting":
      let s = settings[p["key"]!]!
      return "把\(s.label)改成「\(s.show[p["value"]!] ?? p["value"]!)」"
    case "refresh": return "刷新" + (["news": "新闻", "market": "行情", "mail": "邮件", "weather": "天气", "calendar": "日程"][p["what"]!] ?? "")
    case "mail.digest": return "读几封重要邮件的正文，让管家概括（正文会发给你选的 AI）"
    case "open.url": return "在浏览器里打开 \(p["url"]!)"
    default: return "（未知操作）"
    }
  }

  // —— 能直接算出修改的动作 ——
  private static func norm(_ s: String?) -> String { (s ?? "").lowercased().replace("\\s+", "") }

  /** 在自选里找品种：先按代码 / 名字精确匹配，再按包含；0 个或多个都给出明确的错误 */
  static func findWatch(_ watch: [String], _ quotes: [String: Quote], _ query: String) -> (key: String?, error: String?) {
    let q = norm(query)
    let exact = watch.filter { k in [k, quotes[k]?.code, quotes[k]?.name].contains { norm($0) == q } }
    let found = exact.isEmpty ? watch.filter { k in norm(quotes[k]?.name).contains(q) || norm(quotes[k]?.code).contains(q) } : exact
    if found.count == 1 { return (found[0], nil) }
    if found.isEmpty { return (nil, "自选里没有「\(query)」（先让我把它加进自选）") }
    return (nil, "「\(query)」在自选里对应不止一个品种，说得具体一点")
  }

  private static func findReminder(_ list: [JSON], _ title: String) -> (r: JSON?, error: String?) {
    let t = norm(title)
    let exact = list.filter { norm($0["title"] as? String) == t }
    let found = exact.isEmpty ? list.filter { norm($0["title"] as? String).contains(t) } : exact
    if found.count == 1 { return (found[0], nil) }
    return (nil, found.isEmpty ? "没有叫「\(title)」的提醒" : "有好几条提醒都叫类似「\(title)」的名字，说得具体一点")
  }

  /** 返回要写回设置的修改和一句结果；做不了就返回错误。异步类动作（asyncActions）不在这里 */
  static func storePatch(_ a: Action, store: JSON, quotes: [String: Quote]) -> (patch: JSON?, note: String?, error: String?) {
    let watch = store["watch"] as? [String] ?? Market.defaultWatch
    let reminders = store["reminders"] as? [JSON] ?? []
    let p = a.p
    switch a.kind {
    case "watch.remove":
      let f = findWatch(watch, quotes, p["query"]!)
      guard let key = f.key else { return (nil, nil, f.error) }
      var plans = store["plans"] as? JSON ?? [:]
      plans[key] = nil
      return (["watch": watch.filter { $0 != key }, "plans": plans], "已移除「\(p["query"]!)」", nil)
    case "plan.set":
      let f = findWatch(watch, quotes, p["query"]!)
      guard let key = f.key else { return (nil, nil, f.error) }
      var plans = store["plans"] as? JSON ?? [:]
      var cur = plans[key] as? JSON ?? [:]
      if let b = a.num("buy") { cur["buy"] = b }
      if let s = a.num("sell") { cur["sell"] = s }
      if let n = p["note"] { cur["note"] = n }
      plans[key] = cur
      return (["plans": plans], "已记下「\(p["query"]!)」的计划", nil)
    case "alert.price":
      let f = findWatch(watch, quotes, p["query"]!)
      guard let key = f.key else { return (nil, nil, f.error) }
      var all = store["priceAlerts"] as? JSON ?? [:]
      var v: JSON = [:]
      if let x = a.num("above") { v["above"] = x }
      if let x = a.num("below") { v["below"] = x }
      all[key] = v
      return (["priceAlerts": all], "已设好「\(p["query"]!)」的价格提醒", nil)
    case "alert.pct":
      let v = a.num("value") ?? 0
      return (["alertPct": v], v == 0 ? "已关闭涨跌幅通知" : "涨跌幅超过 \(jsNum(v))% 会通知你", nil)
    case "reminder.add":
      let hasPrompt = !(p["prompt"] ?? "").isEmpty
      let r = Reminders.new(title: p["title"]!, time: p["time"]!, days: a.days, prompt: p["prompt"] ?? "",
                            context: ["calendar": hasPrompt, "mail": hasPrompt, "market": false, "quant": false])
      return (["reminders": reminders + [r]], "已新建提醒「\(p["title"]!)」", nil)
    case "reminder.remove":
      let f = findReminder(reminders, p["title"]!)
      guard let r = f.r, let id = r["id"] as? String else { return (nil, nil, f.error) }
      return (["reminders": reminders.filter { $0["id"] as? String != id }], "已删除提醒「\(r["title"] as? String ?? "")」", nil)
    case "reminder.toggle":
      let f = findReminder(reminders, p["title"]!)
      guard let r = f.r, let id = r["id"] as? String else { return (nil, nil, f.error) }
      let on = a.enabled == true
      return (["reminders": reminders.map { x in var y = x; if y["id"] as? String == id { y["enabled"] = on }; return y }],
              "已\(on ? "开启" : "关闭")提醒「\(r["title"] as? String ?? "")」", nil)
    case "widget.show": return (["layout": toggle(store["layout"], p["id"]!, true).json], "已显示「\(widgetDef(p["id"]!)!.label)」", nil)
    case "widget.hide": return (["layout": toggle(store["layout"], p["id"]!, false).json], "已收起「\(widgetDef(p["id"]!)!.label)」", nil)
    case "widget.size": return (["layout": setSize(store["layout"], p["id"]!, p["size"]!).json], "已调整「\(widgetDef(p["id"]!)!.label)」的大小", nil)
    case "setting": return ([p["key"]!: p["value"]!], "已把\(settings[p["key"]!]!.label)改好", nil)
    default: return (nil, nil, "这个操作需要联网或界面配合，不能直接生成修改")
    }
  }
}

extension String {
  func trimmingTrailing() -> String {
    var s = self
    while let c = s.last, c.isWhitespace { s.removeLast() }
    return s
  }
}

// —— 新浪的名称搜索：「腾讯」→ 腾讯控股（rt_hk00700）。旧版只认代码和几个别名，说名字会失败 ——
enum SymbolSearch {
  static func url(_ q: String) -> URL {
    URL(string: "https://suggest3.sinajs.cn/suggest/type=11,12,31,41&key=" + (q.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? q))!
  }

  /** var suggestvalue="名称,类型,代码,完整代码,…;…" → 最合适的新浪代码。类型 11 A 股 / 31 港股 / 41 美股 */
  static func pick(_ text: String, query: String) -> String? {
    guard let body = text.match("suggestvalue=\"([^\"]*)\"")?[1] else { return nil }
    let rows: [(name: String, type: String, key: String)] = body.components(separatedBy: ";").compactMap { row in
      let f = row.components(separatedBy: ",")
      guard f.count >= 4 else { return nil }
      switch f[1] {
      case "11", "12": return (f[0], f[1], f[3].lowercased())
      case "31": return (f[0], f[1], "rt_hk" + f[2])
      case "41": return (f[0], f[1], "gb_" + f[2].lowercased().replacingOccurrences(of: ".", with: "$"))
      default: return nil
      }
    }
    let q = query.trimmed().lowercased()
    let home = rows.filter { $0.type != "41" }      // A 股、港股优先：「腾讯」应该是腾讯控股，不是美股场外的 TCTZF
    let shortest = { (l: [(name: String, type: String, key: String)]) in l.min { $0.name.count < $1.name.count }?.key }
    return home.first { $0.name.lowercased() == q }?.key
      ?? shortest(home.filter { $0.name.lowercased().hasPrefix(q) })
      ?? rows.first { $0.name.lowercased() == q }?.key
      ?? shortest(home.filter { $0.name.lowercased().contains(q) })
      ?? rows.first?.key
  }
}
