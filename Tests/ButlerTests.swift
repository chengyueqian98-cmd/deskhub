// 管家：四象限、配额降级、跨天、去重（brief.test.js）+ 候选提取（candidates.test.js）+ 计划价（plans.test.js）
import Foundation

private func C(_ id: String, _ a: Int, _ s: Int, _ kind: String = "x", urgency: Int = 0) -> Candidate {
  Candidate(id: id, kind: kind, actionable: a, surprise: s, urgency: urgency, facts: ["subject": id])
}
/** 2026-10-20 09:00 美东（测试和 Electron 版一样假设本机在美东时区） */
private let NOW = ISO8601DateFormatter().date(from: "2026-10-20T13:00:00Z")!.timeIntervalSince1970 * 1000

func briefTests() {
  test("四象限落位：只有「可执行且意外」才配打断") {
    eq(Brief.levelOf(C("a", 3, 3)), "notify")
    eq(Brief.levelOf(C("b", 3, 1)), "overlay")
    eq(Brief.levelOf(C("c", 1, 3)), "desk")
    eq(Brief.levelOf(C("d", 1, 1)), nil)
  }
  test("分数 = 可执行 × 意外，且上限 3×3") {
    eq(Brief.scoreOf(C("a", 3, 3)), 9)
    eq(Brief.scoreOf(C("c", 99, 99)), 9)
  }
  test("低可执行 + 低意外：永不出现，且记进 dropped") {
    let r = Brief.plan([C("noise", 1, 1)], now: NOW)
    eq(r.flat.count, 0); eq(r.dropped.first?.why, "never")
  }
  test("按分数从高到低排") {
    eq(Brief.plan([C("low", 1, 3), C("high", 3, 3), C("mid", 3, 1)], now: NOW).flat.map(\.id), ["high", "mid", "low"])
  }
  test("通知配额只给 1 条：第 2 条降级到浮层，不丢") {
    let r = Brief.plan([C("a", 3, 3), C("b", 3, 2)], now: NOW)
    eq(r.notify.map(\.id), ["a"]); eq(r.overlay.first?.id, "b"); eq(r.overlay.first?.downgraded, true)
    ok(r.notes.joined().contains("降级"))
  }
  test("浮层配额用满后继续降级到桌面层，信息一条不少") {
    let r = Brief.plan([C("a", 3, 1), C("b", 3, 1), C("c", 3, 1)], now: NOW, limits: (1, 2))
    eq(r.overlay.count, 2); eq(r.desk.count, 1); eq(r.flat.count, 3)
  }
  test("配额跨天自动重置，同一天累加") {
    let d1 = Brief.plan([C("a", 3, 3)], now: NOW)
    let again = Brief.plan([C("b", 3, 3)], state: d1.state, now: NOW + 3600e3)
    eq(again.notify.count, 0); eq(again.state.notify, 1)
    let next = Brief.plan([C("c", 3, 3)], state: again.state, now: NOW + 26 * 3600e3)
    eq(next.notify.count, 1)
  }
  test("同一件事 12 小时内不重复说") {
    let r1 = Brief.plan([C("m", 3, 3)], now: NOW)
    let r2 = Brief.plan([C("m", 3, 3)], state: r1.state, now: NOW + 2 * 3600e3)
    eq(r2.flat.count, 0); eq(r2.dropped.first?.why, "repeat")
    eq(Brief.plan([C("m", 3, 3)], state: r2.state, now: NOW + 13 * 3600e3).flat.count, 1)
  }
  test("没有 id 的候选直接丢弃") {
    let r = Brief.plan([C("", 3, 3)], now: NOW)
    eq(r.flat.count, 0); eq(r.dropped.first?.why, "no-id")
  }
  test("同分时按 urgency 决定谁上通知，绝不按 id 字母序") {
    let r = Brief.plan([C("aaa-邮件", 3, 3, urgency: 1), C("zzz-止损", 3, 3, urgency: 3)], now: NOW)
    eq(r.notify.first?.id, "zzz-止损")
  }
  test("urgency 也同分时，按传入顺序") {
    eq(Brief.plan([C("second", 3, 3), C("first", 3, 3)], now: NOW).notify.first?.id, "second")
  }
  test("管家的一天：没有新事情不重排；跨天清空；晚点移除") {
    var day = ButlerDay()
    day.refresh([C("a", 3, 3), C("b", 1, 3)], now: NOW)
    eq(day.shown.map(\.id), ["a", "b"])
    eq(day.important.map(\.id), ["a"])
    ok(day.hasNew(seen: [:])); ok(!day.hasNew(seen: ["a": NOW]))
    day.refresh([C("a", 3, 3)], now: NOW + 60e3)
    eq(day.state?.notify, 1, "没有新事情就不重排、不消耗配额")
    day.snooze("b"); eq(day.shown.map(\.id), ["a"])
    day.refresh([C("c", 3, 1)], now: NOW + 26 * 3600e3)
    eq(day.shown.map(\.id), ["c"], "跨天重来")
  }
  test("模板句：英文名后面补空格；止损带二选一；天气不带问句") {
    eq(Brief.say(Candidate(id: "1", kind: "mail_waiting", actionable: 3, surprise: 3, facts: ["from": "School Registrar", "subject": "Spring"])), "School Registrar 在等你：Spring")
    ok(Brief.say(Candidate(id: "2", kind: "risk_alert", actionable: 3, surprise: 3, facts: ["name": "华天科技", "pct": "-9.15%"])).contains("现在看，还是收盘再看？"))
    eq(Brief.say(Candidate(id: "3", kind: "day_ahead", actionable: 2, surprise: 1, facts: ["temp": "3", "rain": "小雨", "note": "记得带伞"])), "今天 3 度、小雨，记得带伞")
  }
}

private let R = Cands.MailRules(contacts: ["school", "registrar", "咖啡馆"])

private func mail(_ name: String = "School Registrar", email: String = "registrar@school.edu", subject: String = "Spring enrollment", ts: Double? = nil, id: String = "m1") -> MailItem {
  MailItem(name: name, email: email, subject: subject, ts: ts ?? NOW - 3600e3, id: id, account: "school")
}
private func pos(_ pnlPct: Double = -9.15, tType: String = "none", tMsg: String = "") -> QuantPosition {
  QuantPosition(code: "002185", name: "华天科技", shares: 2600, cost: 19.592, price: 17.8, mv: nil, pnl: -4659.2, pnlPct: pnlPct, tType: tType, tMsg: tMsg)
}
private func wx(temp: Int = 3, rain: Int = 70, text: String = "小雨") -> Weather {
  Weather(city: "波士顿", at: NOW, now: WxNow(temp: temp, feels: temp - 2, humidity: 80, wind: 10, text: text, icon: "rain"), days: [WxDay(date: "2026-10-20", max: 8, min: 2, rain: rain, text: text, icon: "rain")])
}

func candidateTests() {
  test("名单是用户自己填的：没填就没有「有人在等你」；AI 判断为重要的也算") {
    eq(Cands.mail([mail()], NOW).count, 0)
    eq(Cands.mail([mail()], NOW, rules: Cands.MailRules(contacts: [], aiHits: ["m1"])).first?.kind, "mail_waiting")
    eq(Cands.mail([mail("Chase", email: "a@chase.com", subject: "statement", id: "c")], NOW, rules: Cands.MailRules(money: false)).count, 0, "关掉银行那一档")
    eq(Cands.mail([mail("x", email: "a@b.com", subject: "a.b(c)", id: "z")], NOW, rules: Cands.MailRules(contacts: ["a.b(c)"])).count, 1, "名单里的特殊字符按原样匹配")
  }
  test("白名单发件人 + 近 3 天 → 有人在等你") {
    let c = Cands.mail([mail()], NOW, rules: R).first!
    eq(c.kind, "mail_waiting"); eq(c.actionable, 3); eq(c.action?.type, "mail"); eq(c.facts["from"], "School Registrar")
    ok(c.evidence.contains("registrar@school.edu"))
  }
  test("非白名单不算；超过 3 天的不算") {
    eq(Cands.mail([mail("Promo", email: "a@shop.com", subject: "50% off")], NOW, rules: R).count, 0)
    eq(Cands.mail([mail(ts: NOW - 5 * 86400e3)], NOW, rules: R).count, 0)
  }
  test("主题命中白名单也算") {
    eq(Cands.mail([mail("阿杰", email: "jie@x.com", subject: "咖啡馆的合作想聊聊")], NOW, rules: R).first?.kind, "mail_waiting")
  }
  test("银行/转账：进浮层末位；促销不算；带欺诈字眼升最高档") {
    let c = Cands.mail([mail("Bank of America", email: "alerts@bofa.com", subject: "Zelle® payment of $10.00 has been sent", id: "b1")], NOW, rules: R).first!
    eq(c.kind, "mail_money"); eq(Brief.levelOf(c), "overlay")
    eq(Cands.mail([mail("Agoda Price Alerts", email: "a@agoda.com", subject: "top price drops in New York", id: "a1")], NOW, rules: R).count, 0)
    let f = Cands.mail([mail("Chase", email: "a@chase.com", subject: "Suspicious activity on your account", id: "c1")], NOW, rules: R).first!
    eq(Brief.levelOf(f), "notify")
  }
  test("命中白名单就不再重复算银行那一档；没有 id 不给按钮") {
    let l = Cands.mail([mail(subject: "School tuition payment due")], NOW, rules: R)
    eq(l.count, 1); eq(l.first?.kind, "mail_waiting")
    let n = Cands.mail([mail(id: "")], NOW, rules: R).first!
    ok(n.action == nil); ok(n.id.hasPrefix("mail:"))
  }
  test("持仓跌破止损线 → 最高优先级") {
    let c = Cands.risk(QuantState(positions: [pos()])).first!
    eq(c.kind, "risk_alert"); eq(c.urgency, 3); eq(c.facts["pct"], "-9.15%"); ok(c.id.hasSuffix(":sl"))
    ok(c.evidence.contains { $0.contains("-8") })
  }
  test("量化系统停机：降为旧账，只挂着") {
    let c = Cands.risk(QuantState(running: false, updatedAt: "2026-10-20 01:12:43", positions: [pos()]), NOW).first!
    eq(c.kind, "risk_stale"); eq(c.facts["asOf"], "10-20 01:12"); ok(c.id.hasSuffix(":stale")); eq(Brief.levelOf(c), "desk")
    eq(Cands.risk(QuantState(running: true, updatedAt: "2026-10-20 08:59:00", positions: [pos()]), NOW).first?.kind, "risk_alert")
    eq(Cands.risk(QuantState(updatedAt: "2026-10-20 01:12:43", positions: [pos()]), NOW).first?.kind, "risk_stale", "没标 running 但超过 6 小时")
    let late = Cands.risk(QuantState(updatedAt: "2026-10-20 01:12:43", positions: [pos()]), NOW + 24 * 3600e3).first!
    ok(late.evidence.contains { $0.contains("没更新") })
  }
  test("小亏且没信号不打扰；做 T 信号紧迫度低于止损") {
    eq(Cands.risk(QuantState(positions: [pos(-3)])).count, 0)
    let t = Cands.risk(QuantState(positions: [pos(-1, tType: "t_buy", tMsg: "偏离 MA20 过多")])).first!
    eq(t.urgency, 2); ok(t.id.hasSuffix(":t_buy"))
  }
  test("雨天或低温才占一行；晴天不打扰") {
    let r = Cands.day(wx(), NOW).first!
    eq(r.kind, "day_ahead"); ok(r.evidence.contains { $0.contains("70%") })
    eq(Cands.day(wx(temp: 20, rain: 10, text: "晴"), NOW).count, 0)
    ok(Cands.day(wx(temp: 3, rain: 0, text: "晴"), NOW).first!.facts["note"]!.contains("多穿"))
  }
  test("汇总顺序：钱在前，邮件其次，天气最后") {
    var s = Cands.Inputs()
    s.quant = QuantState(positions: [pos()]); s.mail = [mail()]; s.mailRules = R; s.weather = wx()
    eq(Cands.all(s, NOW).map(\.kind), ["risk_alert", "mail_waiting", "day_ahead"])
    eq(Cands.all(Cands.Inputs(), NOW).count, 0)
  }
  test("日程：20 分钟内开始才提醒") {
    let c = CalendarState(ok: true, events: [
      CalEvent(id: "a", title: "EC202", start: NOW + 8 * 60000, end: NOW + 68 * 60000),
      CalEvent(id: "b", title: "还早", start: NOW + 3 * 3600e3, end: NOW + 4 * 3600e3),
      CalEvent(id: "c", title: "全天", start: NOW + 60000, end: NOW + 86400e3, allDay: true),
      CalEvent(id: "d", title: "已经开始", start: NOW - 60000, end: NOW + 60000),
    ])
    let l = Cands.calendar(c, NOW)
    eq(l.map { $0.facts["title"]! }, ["EC202"])
    ok(l[0].facts["at"]!.test("^\\d{2}:\\d{2}$"))
    eq(Cands.calendar(CalendarState(ok: false), NOW).count, 0)
  }
  test("自选异动：超过阈值才出，最多三条，按幅度排") {
    var q: [String: Quote] = [:]
    for (k, n, p) in [("a", "甲", 5.0), ("b", "乙", -7), ("c", "丙", 1), ("d", "丁", 4), ("e", "戊", 6)] {
      q[k] = Quote(key: k, code: k.uppercased(), market: "cn", name: n, price: 10, pct: p)
    }
    eq(Cands.watch(q, ["a", "b", "c", "d", "e"], 3, NOW).map { $0.facts["name"]! }, ["乙", "戊", "甲"])
    eq(Cands.watch(q, ["a"], 0, NOW).count, 0)
  }
}

func planTests() {
  let DAY = localMs(2026, 10, 20, 10)
  let q = { (price: Double, failed: Bool) in Quote(key: "sz002185", code: "002185", market: "cn", name: "华天科技", price: price, failed: failed) }
  test("normPlan 把写坏的值当没填") {
    eq(Plans.norm(nil), Plans.Plan(buy: nil, sell: nil, note: ""))
    eq(Plans.norm(["buy": -3, "sell": 0, "note": 5]), Plans.Plan(buy: nil, sell: nil, note: ""))
    eq(Plans.norm(["buy": "14.5", "sell": "18"]), Plans.Plan(buy: 14.5, sell: 18, note: ""))
  }
  test("到价、快到、区间、没设价") {
    eq(Plans.state(Plans.Plan(buy: 15, sell: nil, note: ""), 14.5).side, "under_buy")
    eq(Plans.state(Plans.Plan(buy: nil, sell: 18, note: ""), 18).side, "over_sell")
    eq(Plans.state(Plans.Plan(buy: 15, sell: nil, note: ""), 15 * 1.01).side, "near_buy")
    eq(Plans.state(Plans.Plan(buy: 15, sell: nil, note: ""), 16.5).side, "mid")
    eq(Plans.state(Plans.Plan(buy: nil, sell: 18, note: ""), 18 * 0.99).side, "near_sell")
    eq(Plans.state(Plans.Plan(buy: nil, sell: nil, note: ""), 14).side, "none")
    eq(Plans.state(Plans.Plan(buy: 15, sell: nil, note: ""), 0).side, "none")
  }
  test("distanceText 只说位置") {
    eq(Plans.distanceText(Plans.Plan(buy: 15, sell: nil, note: ""), 14.5), "已低于买入价 3.3%")
    eq(Plans.distanceText(Plans.Plan(buy: nil, sell: 18, note: ""), 18.4), "已高于卖出价 2.2%")
    eq(Plans.distanceText(Plans.Plan(buy: 15, sell: nil, note: ""), 20), "")
  }
  test("到价生成候选；快到级别低一档；跨天重新说") {
    let c = Plans.candidates(["k": q(14.5, false)], ["k": ["buy": 15, "note": "等回踩"]], DAY).first!
    eq(c.kind, "plan_hit"); eq(c.facts["price"], "14.5"); eq(c.facts["target"], "15"); eq(c.facts["which"], "买入价"); eq(c.facts["dir"], "跌破")
    ok(c.evidence.contains { $0.contains("等回踩") }); ok(c.id.hasSuffix("2026-10-20"))
    eq(Plans.candidates(["k": q(20, false)], ["k": ["buy": 15]], DAY).count, 0)
    eq(Plans.candidates(["k": q(14, true)], ["k": ["buy": 15]], DAY).count, 0)
    let near = Plans.candidates(["k": q(15.2, false)], ["k": ["buy": 15]], DAY).first!
    eq(near.facts["dir"], "快到"); ok(near.actionable < c.actionable)
    ok(Plans.candidates(["k": q(14.5, false)], ["k": ["buy": 15]], DAY + 86400e3).first!.id != c.id)
  }
  test("shareOf 与单票上限") {
    eq(Plans.shareOf(21000, 0), nil); eq(Plans.shareOf(nil, 50000), nil); eq(Plans.shareOf(21000, 50000), 42)
    let quant = QuantState(positions: [
      QuantPosition(code: "002185", name: "华天科技", mv: 21000), QuantPosition(code: "00700", name: "腾讯控股", mv: 4000),
    ])
    let l = Plans.capCandidates(quant, acctSize: 50000, maxPerPct: 20, DAY)
    eq(l.map { $0.facts["name"]! }, ["华天科技"]); eq(l[0].facts["share"], "42%"); eq(l[0].facts["cap"], "20%")
    eq(Plans.capCandidates(quant, acctSize: 0, maxPerPct: 20, DAY).count, 0)
  }
}
