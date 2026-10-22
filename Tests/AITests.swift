// 自然语言办事（actions.test.js）、提醒调度、Claude 输出解析、歌词、名称搜索
import Foundation

private func act(_ json: String) -> ActionCheck { Actions.check(try! JSONSerialization.jsonObject(with: Data(json.utf8))) }

func aiTests() {
  test("取 actions 块：只认第一块，显示文字里去掉；没闭合的也先藏起来") {
    let r = Actions.extract("好的，我来加。\n```actions\n[{\"do\":\"watch.add\",\"query\":\"腾讯\"}]\n```\n```actions\n[{\"do\":\"nav\",\"page\":\"news\"}]\n```")
    eq(r.text, "好的，我来加。"); eq(r.raw?.count, 1); eq(r.error, nil)
    eq(Actions.extract("正在…\n```actions\n[{\"do\"").text, "正在…")
    eq(Actions.extract("```actions\n{\"do\":1}\n```").error, "actions 不是数组")
    ok(Actions.extract("```actions\n[坏的\n```").error != nil)
  }
  test("白名单：认识的动作逐字段校验，不认识的拒绝") {
    ok(act("{\"do\":\"watch.add\",\"query\":\"腾讯\"}").ok)
    ok(!act("{\"do\":\"order.buy\",\"query\":\"腾讯\"}").ok, "下单必须拒绝")
    ok(!act("{\"do\":\"mail.send\"}").ok, "发邮件必须拒绝")
    ok(!act("{\"do\":\"plan.set\",\"query\":\"腾讯\",\"buy\":-1}").ok)
    ok(!act("{\"do\":\"plan.set\",\"query\":\"腾讯\"}").ok, "什么都没填")
    eq(act("{\"do\":\"plan.set\",\"query\":\"腾讯\",\"buy\":\"350\"}").action?.p["buy"], "350")
    ok(!act("{\"do\":\"alert.pct\",\"value\":50}").ok)
    ok(!act("{\"do\":\"open.url\",\"url\":\"http://a.com\"}").ok, "只能 https")
    ok(!act("{\"do\":\"open.url\",\"url\":\"javascript:alert(1)\"}").ok)
    ok(act("{\"do\":\"open.url\",\"url\":\"https://a.com/x\"}").ok)
    ok(!act("{\"do\":\"widget.show\",\"id\":\"__proto__\"}").ok, "原型链上的名字不能当组件")
    ok(!act("{\"do\":\"widget.size\",\"id\":\"calendar\",\"size\":\"S\"}").ok)
    ok(!act("{\"do\":\"setting\",\"key\":\"quantDir\",\"value\":\"/\"}").ok, "量化目录不能由管家改")
    ok(!act("{\"do\":\"setting\",\"key\":\"aiAgent\",\"value\":\"openclaw\"}").ok, "OpenClaw 不再接")
    ok(!act("{\"do\":\"reminder.toggle\",\"title\":\"a\",\"enabled\":1}").ok, "enabled 必须是布尔值")
  }
  test("提醒：时间、星期的写法") {
    eq(Actions.normTime("8:05"), "08:05"); eq(Actions.normTime("25:00"), nil); eq(Actions.normTime("8：30"), "08:30")
    eq(Actions.normDays("weekdays"), [1, 2, 3, 4, 5]); eq(Actions.normDays([7, 1, 1]), [1, 7]); eq(Actions.normDays([]), []); eq(Actions.normDays([9]), nil)
    let a = act("{\"do\":\"reminder.add\",\"title\":\"交作业\",\"time\":\"8:00\",\"days\":\"weekdays\"}").action!
    eq(Actions.describe(a), "新建提醒：工作日 08:00「交作业」")
  }
  test("一次最多 6 件，多的写明") {
    let raw = (0..<8).map { _ in ["do": "mail.digest"] as JSON }
    let l = Actions.checkAll(raw)
    eq(l.count, 7); eq(l.filter(\.ok).count, 6); ok(l.last!.error!.contains("2 件"))
  }
  test("确认卡的说明由校验后的参数生成") {
    eq(Actions.describe(act("{\"do\":\"plan.set\",\"query\":\"腾讯\",\"buy\":350,\"note\":\"等回踩\"}").action!), "给「腾讯」记下：买入价 350、观察「等回踩」（只是记下，不会下单）")
    eq(Actions.describe(act("{\"do\":\"setting\",\"key\":\"colors\",\"value\":\"rup\"}").action!), "把涨跌颜色改成「红涨绿跌」")
  }
  test("直接算修改：自选里找品种、记计划、删提醒") {
    let quotes = ["rt_hk00700": Quote(key: "rt_hk00700", code: "00700", market: "hk", name: "腾讯控股"),
                  "gb_aapl": Quote(key: "gb_aapl", code: "AAPL", market: "us", name: "苹果")]
    let store: JSON = ["watch": ["rt_hk00700", "gb_aapl"], "plans": [:] as JSON,
                       "reminders": [["id": "r1", "title": "早间简报", "enabled": true]] as [JSON]]
    let p = Actions.storePatch(act("{\"do\":\"plan.set\",\"query\":\"腾讯\",\"buy\":350}").action!, store: store, quotes: quotes)
    eq(((p.patch?["plans"] as? JSON)?["rt_hk00700"] as? JSON)?["buy"] as? Double, 350)
    eq(Actions.storePatch(act("{\"do\":\"watch.remove\",\"query\":\"茅台\"}").action!, store: store, quotes: quotes).error, "自选里没有「茅台」（先让我把它加进自选）")
    let r = Actions.storePatch(act("{\"do\":\"reminder.remove\",\"title\":\"简报\"}").action!, store: store, quotes: quotes)
    eq((r.patch?["reminders"] as? [JSON])?.count, 0)
    let w = Actions.storePatch(act("{\"do\":\"widget.show\",\"id\":\"news\"}").action!, store: store, quotes: quotes)
    eq(normalize(w.patch?["layout"]).item("news")?.on, true)
  }
  test("名称搜索：腾讯 → 腾讯控股（港股优先于美股场外），苹果 → AAPL") {
    let t = "var suggestvalue=\"腾讯,41,tctzf,tctzf,腾讯,,腾讯,99,1,,,;腾讯控股,31,00700,00700,腾讯控股,,腾讯控股,99,1,ESG,,;腾讯济安,11,000847,sh000847,腾讯济安,,腾讯济安,99,1,,,\";"
    eq(SymbolSearch.pick(t, query: "腾讯"), "rt_hk00700")
    eq(SymbolSearch.pick("var suggestvalue=\"苹果,41,aapl,aapl,苹果,,苹果,99,1,ESG,,\";", query: "苹果"), "gb_aapl")
    eq(SymbolSearch.pick("var suggestvalue=\"贵州茅台,11,600519,sh600519,贵州茅台,,贵州茅台,99,1,ESG,,\";", query: "茅台"), "sh600519")
    eq(SymbolSearch.pick("var suggestvalue=\"\";", query: "x"), nil)
  }
  test("提醒调度：到点、选中的星期、当天只跑一次、错过 2 小时不补") {
    let r: JSON = ["id": "a", "time": "08:00", "days": [1, 2, 3, 4, 5], "enabled": true]
    let tue = { (h: Int, m: Int) in localMs(2026, 10, 20, h, m) }
    eq(Reminders.due([r], now: tue(7, 59)).count, 0); eq(Reminders.due([r], now: tue(8, 0)).count, 1)
    eq(Reminders.due([r], now: tue(9, 59)).count, 1); eq(Reminders.due([r], now: tue(10, 1)).count, 0)
    var ran = r; ran["lastRunDay"] = "2026-10-20"
    eq(Reminders.due([ran], now: tue(8, 5)).count, 0)
    eq(Reminders.due([r], now: localMs(2026, 10, 24, 8, 5)).count, 0, "周六")
    var every = r; every["days"] = [Int]()
    eq(Reminders.due([every], now: localMs(2026, 10, 24, 8, 5)).count, 1)
    eq(Reminders.nextRun(ran, now: tue(9, 0)), localMs(2026, 10, 21, 8, 0))
    eq(Reminders.nextRun(r, now: localMs(2026, 10, 23, 20, 0)), localMs(2026, 10, 26, 8, 0))
    let p = Reminders.buildPrompt(["prompt": "总结一下"], calendar: "9:00 上课", mail: nil, market: "华天科技 +2%", quant: nil)
    ok(p.contains("【日程】\n9:00 上课")); ok(p.contains("【自选行情")); ok(!p.contains("【未读邮件")); ok(p.contains("不要给出任何买入、卖出或持有的建议"))
    eq(Reminders.notifyBody("## 标题\n\n**重点**"), "标题\n重点")
  }
  test("Claude 命令行输出：会话、文字、工具、结果、没登录") {
    eq(ClaudeStream.parse("{\"type\":\"system\",\"subtype\":\"init\",\"session_id\":\"s1\"}"), [.session("s1")])
    let a = ClaudeStream.parse("{\"type\":\"assistant\",\"message\":{\"content\":[{\"type\":\"text\",\"text\":\"好\"},{\"type\":\"tool_use\",\"id\":\"t1\",\"name\":\"Read\",\"input\":{\"file_path\":\"/a.txt\"}}]}}")
    eq(a, [.text("好"), .tool(id: "t1", title: "读文件", detail: "/a.txt")])
    var items: [TItem] = []
    for e in a { ClaudeStream.apply(e, to: &items) }
    for e in ClaudeStream.parse("{\"type\":\"user\",\"message\":{\"content\":[{\"type\":\"tool_result\",\"tool_use_id\":\"t1\",\"is_error\":true,\"content\":\"没有这个文件\"}]}}") { ClaudeStream.apply(e, to: &items) }
    eq(items.count, 2); eq(items[1].failed, true)
    let done = ClaudeStream.parse("{\"type\":\"result\",\"subtype\":\"success\",\"is_error\":true,\"result\":\"Not logged in · Please run /login\"}")
    for e in done { ClaudeStream.apply(e, to: &items) }
    ok(items.last!.text.contains("还没登录"))
    eq(ClaudeStream.parse("不是 JSON"), [])
  }
  test("Claude 会话记录：系统注入的、工具结果不当成用户的话") {
    ok(ClaudeSessions.userText(["type": "user", "message": ["content": "帮我看看"]]) == "帮我看看")
    ok(ClaudeSessions.userText(["type": "user", "isMeta": true, "message": ["content": "x"]]) == nil)
    ok(ClaudeSessions.userText(["type": "user", "message": ["content": "<command-name>/clear</command-name>"]]) == nil)
    ok(ClaudeSessions.userText(["type": "user", "message": ["content": [["type": "tool_result", "content": "x"]]]]) == nil)
  }
  test("歌词：解析 LRC、按进度找行、挑时长最接近的") {
    let lines = Lyrics.parse("[ti:晴天]\n[00:01.50]故事的小黄花\n[00:05.00][01:05.00]从出生那年就飘着\n[00:09.20]\n")
    eq(lines.map(\.t), [1.5, 5, 9.2, 65])
    eq(Lyrics.lineAt(lines, 0.5), -1); eq(lines[Lyrics.lineAt(lines, 6)].text, "从出生那年就飘着")
    eq(Lyrics.parseNowPlaying("stopped")?.title, nil)
    let np = Lyrics.parseNowPlaying("playing\u{1f}晴天\u{1f}周杰伦\u{1f}叶惠美\u{1f}269,5\u{1f}12.25\n")!
    eq(np.duration, 269.5); eq(np.position, 12.25); eq(np.playing, true)
    let best = Lyrics.pickBest([["duration": 260, "syncedLyrics": "a"], ["duration": 247, "syncedLyrics": "b"], ["duration": 246, "plainLyrics": "c"]], duration: 246)
    eq(best?["syncedLyrics"] as? String, "b")
    ok(Lyrics.pickBest([["duration": 300, "syncedLyrics": "x"]], duration: 246) == nil)
  }
  test("抽屉、内存、K 线") {
    eq(DeskFiles.kindOf("a.docx", isDir: false), "doc"); eq(DeskFiles.kindOf("微信.app", isDir: true), "app"); eq(DeskFiles.kindOf("课程", isDir: true), "folder")
    ok(DeskFiles.item(".DS_Store", isDir: false) == nil); ok(DeskFiles.item("~$a.docx", isDir: false) == nil)
    eq(DeskFiles.item(".报告.pdf.icloud", isDir: false)?.name, "报告.pdf"); eq(DeskFiles.item(".报告.pdf.icloud", isDir: false)?.cloud, true)
    eq(SysInfo.parseVmStat("Mach Virtual Memory Statistics: (page size of 16384 bytes)\nPages active:   100.\nPages wired down:   50.\nPages occupied by compressor:   10.\nPages inactive: 999.\n"), 160 * 16384)
    var rows: [JSON] = []
    for i in 0..<25 {
      let d = Double(i)
      let r: JSON = ["day": "2026-09-" + pad2(i + 1), "open": 10 + d, "high": 11 + d, "low": 9 + d, "close": 10.5 + d]
      rows.append(r)
    }
    let k = KLine.fromSina(rows)
    eq(k.ma10[8] ?? -1, -1); eq(k.ma10[9] ?? 0, 15); eq(k.ma20[19] ?? 0, 20)
  }
}

func extraTests() {
  test("同一种组件加好几个：id 是「种类-数字」，各自有位置，删掉后不影响别人") {
    let a = addInstance(DEFAULT_LAYOUT, "market")
    eq(a.id, "market-2")
    let it = a.layout.item("market-2")!
    eq(it.type, "market"); eq(it.on, true); ok(it.row + it.h <= Grid.rows)
    let b = addInstance(a.layout.json, "market")
    eq(b.id, "market-3")
    eq(normalize(b.layout.json).items.filter { $0.type == "market" }.count, 3, "存盘再读回来还在")
    eq(addInstance(DEFAULT_LAYOUT, "clock").id, nil, "时钟不能加第二个")
    let r = removeInstance(b.layout.json, "market-2")
    ok(r.item("market-2") == nil); ok(r.item("market-3") != nil)
    eq(removeInstance(DEFAULT_LAYOUT, "market").item("market")?.on, false, "每种的第一个只是收起")
    eq(typeOf("market-12"), "market"); eq(typeOf("clock"), "clock"); eq(typeOf("clock-2"), "clock")
    ok(normalize(["version": Grid.version, "items": [["id": "clock-2", "on": true]]]).item("clock-2") == nil, "不能多开的种类，假 id 丢掉")
    eq(setSize(b.layout.json, "market-3", "T").item("market-3")?.h, 3)
  }
  test("四种身份的默认布局：合法、不重叠、中间留空") {
    for p in ["student", "work", "invest", "minimal"] {
      let L = normalize(presetLayout(p))
      let on = L.items.filter(\.on)
      ok(on.count >= 3, p)
      for i in on.indices { for j in on.indices where j > i { ok(!overlaps((on[i].col, on[i].row, on[i].w, on[i].h), (on[j].col, on[j].row, on[j].w, on[j].h)), p) } }
      ok(on.allSatisfy { $0.col + $0.w <= 2 || $0.col >= 6 }, p)
    }
    ok(normalize(presetLayout("student")).item("todo")?.on == true)
  }
  test("加密货币、GitHub、倒数日、Atom") {
    eq(Crypto.id("BTC"), "bitcoin"); eq(Crypto.id("比特币"), "bitcoin"); eq(Crypto.id("pepe"), "pepe")
    let q = Crypto.parse(["bitcoin": ["usd": 67000.5, "usd_24h_change": -1.2]], ids: ["bitcoin", "ethereum"], vs: "usd")
    eq(q, [CoinQuote(id: "bitcoin", price: 67000.5, change: -1.2)])
    eq(GitHubAPI.parseRepo(["full_name": "a/b", "stargazers_count": 12, "forks_count": 3, "open_issues_count": 1])?.stars, 12)
    eq(GitHubAPI.totalDownloads([["assets": [["download_count": 5], ["download_count": 7]]], ["assets": [["download_count": 1]]]]), 13)
    eq(Countdown.days("2026-12-25", now: localMs(2026, 10, 22, 15)), 64); eq(Countdown.days("2026-10-20", now: localMs(2026, 10, 22)), -2); eq(Countdown.days("x"), nil)
    let atom = "<feed><title>我的博客</title><entry><title>新文章</title><link href=\"https://a.com/1\"/><updated>2026-10-20T10:00:00Z</updated></entry></feed>"
    eq(News.parseFeed(atom, source: "x").first?.title, "新文章"); eq(News.feedTitle(atom), "我的博客")
  }
  test("英文界面：查不到翻译就显示原文；管家话术有英文版") {
    appLang = "en"
    eq(L("这句没有翻译"), "这句没有翻译")
    ok(Brief.say(Candidate(id: "1", kind: "watch_move", actionable: 1, surprise: 2, facts: ["name": "AAPL", "pct": "+3%"])).contains("today"))
    appLang = "zh"
    eq(Brief.say(Candidate(id: "1", kind: "watch_move", actionable: 1, surprise: 2, facts: ["name": "AAPL", "pct": "+3%"])), "AAPL 今天 +3%。")
  }
}
