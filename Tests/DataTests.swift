// 行情、新闻、邮件、天气、量化、格式化（desk.test.js / mailNews.test.js）
import Foundation

private let SINA = """
var hq_str_sz002185="华天科技,14.000,13.890,14.230,14.490,14.000,14.230,14.240,112339964,1601173477.050,117200,14.230,323500,14.220,342400,14.210,895400,14.200,86800,14.190,2900,14.240,80400,14.250,83200,14.260,89300,14.270,64000,14.280,2026-10-20,13:31:12,00";
var hq_str_rt_hkHSI="HSI,恒生指数,23990.050,24186.830,24035.000,23868.230,23909.631,-277.200,-1.150,0.000,0.000,117530825.755,6281236678,0.000,0.000,28056.100,22518.000,2026/10/20,13:31:13,,,,,,";
var hq_str_gb_aapl="苹果,342.9400,-0.15,2026-10-20 07:59:42,-0.5200,340.7750,346.0000,340.1150,348.1500,242.8900,34666420,38687021";
var hq_str_sh600000="";
"""

private func utc(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ mi: Int) -> Double {
  var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
  return cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: mi))!.timeIntervalSince1970 * 1000
}

func marketTests() {
  test("代码识别：A 股按首位分沪深，港股补 0，美股小写，中文别名") {
    eq(Market.toSinaKey("600519"), "sh600519"); eq(Market.toSinaKey("002185"), "sz002185"); eq(Market.toSinaKey("300750"), "sz300750")
    eq(Market.toSinaKey("830799"), "bj830799"); eq(Market.toSinaKey("700"), "rt_hk00700"); eq(Market.toSinaKey("00700.HK"), "rt_hk00700")
    eq(Market.toSinaKey("AAPL"), "gb_aapl"); eq(Market.toSinaKey("BRK.B"), "gb_brk$b"); eq(Market.toSinaKey("恒指"), "rt_hkHSI")
    eq(Market.toSinaKey("上证指数"), "sh000001"); eq(Market.toSinaKey(""), nil); eq(Market.toSinaKey("？？"), nil)
    eq(Market.displayCode("gb_brk$b"), "BRK.B")
  }
  test("解析新浪三种市场的返回") {
    let raw = Market.splitResponse(SINA)
    let a = try! Market.parseQuote("sz002185", raw["sz002185"]!)
    eq(a.name, "华天科技"); eq(a.price, 14.23); eq(a.prev, 13.89); eq(a.pct, 2.45); eq(a.market, "cn")
    eq(a.ts, Market.bjToMs("2026-10-20", "13:31:12"))
    let h = try! Market.parseQuote("rt_hkHSI", raw["rt_hkHSI"]!)
    eq(h.name, "恒生指数"); eq(h.price, 23909.631); eq(h.pct, -1.15); eq(h.index, true)
    let u = try! Market.parseQuote("gb_aapl", raw["gb_aapl"]!)
    eq(u.price, 342.94); eq(u.prev, 343.46); eq(u.pct, -0.15)
    ok((try? Market.parseQuote("sh600000", raw["sh600000"]!)) == nil)
  }
  test("A 股开盘前现价为 0 时用昨收") {
    let q = try! Market.parseQuote("sh600000", "浦发银行,0.000,10.00,0.000,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,2026-10-20,09:10:00,00")
    eq(q.price, 10); eq(q.pct, 0)
  }
  test("交易时段：按各市场自己的时区判断") {
    let ms = utc(2026, 10, 20, 5, 31)
    eq(Market.isOpen("cn", ms), true); eq(Market.isOpen("hk", ms), true); eq(Market.isOpen("us", ms), false)
    let noon = utc(2026, 10, 20, 4, 0)
    eq(Market.isOpen("cn", noon), false); eq(Market.isOpen("hk", noon), false)
    eq(Market.isOpen("us", utc(2026, 10, 20, 14, 0)), true)
    eq(Market.isOpen("cn", utc(2026, 10, 24, 2, 0)), false)
    eq(Market.quoteStatus(Quote(key: "x", code: "x", market: "cn", ts: ms - 60e3), ms), "live")
    eq(Market.quoteStatus(Quote(key: "x", code: "x", market: "cn", ts: ms - 3600e3), ms), "stale")
    eq(Market.quoteStatus(Quote(key: "x", code: "x", market: "us", ts: ms), ms), "closed")
    eq(Market.quoteStatus(Quote(key: "x", code: "x", market: "cn", failed: true), ms), "fail")
  }
  test("涨跌提醒：超过阈值、到价都提醒，同一天不重复") {
    var memo = Set<String>()
    let qs = [Quote(key: "sz002185", code: "002185", market: "cn", name: "华天科技", price: 14.8, pct: 4.2),
              Quote(key: "gb_aapl", code: "AAPL", market: "us", name: "苹果", price: 300, pct: -1)]
    let prices: JSON = ["gb_aapl": ["below": 310]]
    let a = Market.checkAlerts(qs, pct: 3, prices: prices, memo: &memo, day: "2026-10-20")
    eq(a.count, 2)
    ok(a[0].title.test("华天科技.*涨幅 4\\.20%"), a[0].title)
    ok(a[1].title.contains("苹果（AAPL） 跌到 300"), a[1].title)
    eq(Market.checkAlerts(qs, pct: 3, prices: prices, memo: &memo, day: "2026-10-20").count, 0)
    eq(Market.checkAlerts(qs, pct: 3, prices: prices, memo: &memo, day: "2026-10-21").count, 2)
    var m2 = Set<String>()
    eq(Market.checkAlerts(qs, pct: 0, prices: [:], memo: &m2, day: "d").count, 0)
  }
}

func newsMailTests() {
  test("解析 RSS，跳过没有链接或时间的条目，按时间排序") {
    let xml = """
    <rss><channel><item><title><![CDATA[港股下午初段跌逾1%]]></title><link>https://news.rthk.hk/a.htm</link><description><![CDATA[港股下午開市初段跌逾1%。

    編輯：宋家樑]]></description><pubDate>Tue, 20 Oct 2026 13:18:55 +0800</pubDate></item>
    <item><title>無連結</title><pubDate>Tue, 20 Oct 2026 13:00:00 +0800</pubDate></item>
    <item><title>較早 &amp; 新聞</title><link>https://news.rthk.hk/b.htm</link><pubDate>Tue, 20 Oct 2026 11:00:00 +0800</pubDate></item></channel></rss>
    """
    let items = News.parseRss(xml, tag: "财经")
    eq(items.count, 2)
    eq(items.first?.desc, "港股下午開市初段跌逾1%。")
    eq(items.last?.title, "較早 & 新聞")
    var other = items[1]; other.tag = "国际"
    let merged = News.merge([[other], items])
    eq(merged.count, 2); eq(merged.first?.link, "https://news.rthk.hk/a.htm")
    eq(News.t2s("恆指競價時段"), "恒指竞价时段")
  }
  test("parseRss：没有 link 用 guid；dc:date 也认；坏条目丢掉") {
    let xml = """
    <rss><channel>
    <item><title>甲</title><guid>https://a.com/1</guid><pubDate>Tue, 20 Oct 2026 13:18:55 +0800</pubDate></item>
    <item><title>乙</title><link>https://a.com/2</link><dc:date>2026-10-20T10:00:00+08:00</dc:date></item>
    <item><title>丙</title><link>not-a-url</link><pubDate>Tue, 20 Oct 2026 13:18:55 +0800</pubDate></item>
    </channel></rss>
    """
    let items = News.parseRss(xml, tag: "科技", source: "少数派")
    eq(items.map(\.title), ["甲", "乙"])
    ok(items.allSatisfy { $0.source == "少数派" && $0.tag == "科技" })
  }
  test("新闻来源：id 不重复；pick 不认识或全空就退回默认") {
    let ids = News.sources.map(\.id)
    eq(Set(ids).count, ids.count)
    ok(News.defaultIds.count >= 4)
    eq(News.pick(["bbc", "cnbc"]).map(\.id), ["bbc", "cnbc"])
    eq(News.pick([]).map(\.id), News.defaultIds)
    eq(News.pick(["不存在"]).map(\.id), News.defaultIds)
  }
  test("解析邮件 App 的输出") {
    let US = "\u{1f}", RS = "\u{1e}"
    let out = "12\(RS)张三 <zs@example.com>\(US)作业提醒\(US)2026-10-19 3600\(US)abc@mail\(US)Gmail\(RS)\"Canvas\" <no-reply@canvas.edu>\(US)\(US)2026-10-20 7200\(US)def@mail\(US)学校\n"
    let r = MailAPI.parseOutput(out)
    eq(r.unread, 12); eq(r.items.count, 2)
    eq(r.items[0].name, "Canvas"); eq(r.items[0].subject, "（无主题）")
    eq(r.items[1].email, "zs@example.com")
    eq(r.items[1].ts, localMs(2026, 10, 19) + 3600e3)
    let s = MailAPI.parseSender("a@b.com"); eq([s.name, s.email], ["a@b.com", "a@b.com"])
    eq(MailAPI.messageUrl("x<y>@z"), "message://%3cx%3Cy%3E%40z%3e")
    eq(MailAPI.parseOutput("0").items.count, 0)
  }
}

func miscTests() {
  test("天气代码 → 中文") {
    eq(WeatherAPI.describe(0, 1).text, "晴"); eq(WeatherAPI.describe(0, 0).icon, "moon")
    eq(WeatherAPI.describe(63).text, "中雨"); eq(WeatherAPI.describe(95).icon, "storm")
  }
  test("量化快照：修正今日盈亏和仓位口径；NaN 不会让解析失败") {
    let s = QuantAPI.summarize([
      "updated_at": "2026-10-20 01:12:43",
      "account": ["initial_capital": 52596.1, "cash": 1656.9, "market_value": 37102, "total_asset": 38758.9],
      "risk": ["status": "exit", "cur_drawdown": -22.31, "half_line": -10, "exit_line": -15, "stop_loss_pct": -8],
      "positions": [["code": "002185", "name": "华天科技", "shares": 2600, "cost": 19.592, "price": 14.27, "pct_chg": 2.74, "mv": 37102, "pnl": -13837.2, "pnl_pct": -27.16, "t_signal": ["msg": "已收盘"]]],
    ])
    eq(s.account?.pnl, -13837.2); eq(s.account?.pnlPct, -26.31); eq(s.account?.posRatio, 95.7)
    ok(abs((s.account?.dayPnl ?? 0) - 989.5) < 1)
    eq(s.risk?.drawdown, -22.31); eq(s.positions.first?.tMsg, "已收盘")
    ok(QuantAPI.readJSON(Data("{\"a\": NaN, \"b\": -Infinity}".utf8)) != nil)
  }
  test("电量：解析 pmset，按名字猜类型，短名字") {
    let t = "Now drawing from 'AC Power'\n -InternalBattery-0 (id=23527523)\t100%; charged; 0:00 remaining present: true\n -Mi Mouse4P (id=635901188)\t89%; \n -小明的AirPods Max 2 (id=42800382)\t57%; discharging present: true\n"
    let b = BatteryInfo.parsePmset(t)
    eq(b.count, 3)
    eq([b[0].name, "\(b[0].pct)", "\(b[0].ac)", "\(b[0].charged)", b[0].type], ["Mac", "100", "true", "true", "laptop"])
    eq(b[1].type, "mouse"); eq(b[2].type, "headphones")
    eq(BatteryInfo.shortName("小明的AirPods Max 2"), "AirPods Max")
  }
  test("格式化：涨跌、金额、相对时间、头像字") {
    eq(F.pct(2.456), "+2.46%"); eq(F.pct(-1), "-1.00%"); eq(F.pct(nil), "—")
    eq(F.pctMono(0.12), "▲ 0.12%"); eq(F.pctMono(-1.32), "▼ 1.32%"); eq(F.pctMono(0), "0.00%")
    eq(F.signed(-13837.2, 0), "-13,837"); eq(F.money(38758.9), "¥38,758.90"); eq(F.cls(0), "flat")
    eq(F.price(0.5), "0.500"); eq(F.price(23909.631), "23,909.63")
    let now = localMs(2026, 10, 20, 14)
    eq(F.rel(now - 30e3, now), "刚刚"); eq(F.rel(now - 5 * 60e3, now), "5 分钟前")
    eq(F.rel(localMs(2026, 10, 20, 9, 5), now), "今天 09:05"); eq(F.rel(localMs(2026, 10, 19, 9, 5), now), "昨天 09:05")
    eq(F.dayLabel(localMs(2026, 10, 21, 9), now), "明天")
    eq(F.statusText("live", "hk"), "交易中·延迟约15分钟")
    eq(F.initials("张三丰"), "丰"); eq(F.initials("Canvas Notifications"), "CN")
    eq(F.riskText("exit"), "清仓警戒")
    eq(F.hotkeyLabel("Control+Alt+Space"), "⌃⌥空格")
  }
  test("月历：42 格从周一开始，读取范围覆盖整屏") {
    let cells = F.monthCells(2026, 10)
    eq(cells.count, 42)
    eq(F.dayKey(cells[0].ms), "2026-09-28")
    eq(cells[3].inMonth, true); eq(cells[3].day, 1)
    let r = CalendarRange.range(localMs(2026, 10, 20))
    eq(r.from, localMs(2026, 9, 28)); eq(r.to, localMs(2026, 11, 9))
  }
  test("设置存储：读写同一个 desk.json，不认识的键原样保留") {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("deskhub-test-\(UUID().uuidString)")
    let url = dir.appendingPathComponent("sub/desk.json")
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? Data("{\"aiAgent\":\"deepseek\",\"alertPct\":4}".utf8).write(to: url)
    let s = Store(url: url)
    eq(s.alertPct, 4); ok(s.watch.contains("rt_hk00700")); eq(s.butlerName, "管家")
    var seen: Set<String> = []
    s.onChange = { seen = $0 }
    s.set(["alertPct": 5])
    eq(seen, ["alertPct"])
    let again = Store(url: url)
    eq(again.alertPct, 5); eq(again.data["aiAgent"] as? String, "deepseek")
    try? FileManager.default.removeItem(at: dir)
  }
}

func batteryNotChargingTest() {
  test("电量：接着电源但 not charging 不算充电中") {
    let b = BatteryInfo.parsePmset("Now drawing from 'AC Power'\n -InternalBattery-0 (id=1)\t80%; AC attached; not charging present: true\n")
    eq(b.first?.charging, false); eq(b.first?.ac, true)
  }
}
