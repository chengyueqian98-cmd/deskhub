// 核心逻辑测试（和 Mac 版 Tests/ 同样的用例）。跑法：dotnet run --project DeskHub.Tests
using System.Text.Json.Nodes;
using DeskHub.Core;
using static DeskHub.Core.I18n;

int pass = 0, fail = 0;
string cur = "";

void Test(string name, Action body)
{
    cur = name;
    int before = fail;
    try { body(); } catch (Exception e) { fail++; Console.WriteLine($"✗ {name}：抛出 {e.GetType().Name} {e.Message}\n{e.StackTrace}"); return; }
    if (fail == before) pass++;
}
void Ok(bool c, string msg = "") { if (!c) { fail++; Console.WriteLine($"✗ {cur}：{msg}"); } }
void Eq<T>(T a, T b, string msg = "") { if (!EqualityComparer<T>.Default.Equals(a, b)) { fail++; Console.WriteLine($"✗ {cur}：得到 {a}，应为 {b} {msg}"); } }
void EqL<T>(IEnumerable<T> a, IEnumerable<T> b, string msg = "") { if (!a.SequenceEqual(b)) { fail++; Console.WriteLine($"✗ {cur}：得到 [{string.Join(",", a)}]，应为 [{string.Join(",", b)}] {msg}"); } }

JsonObject J(string s) => JsonNode.Parse(s)!.AsObject();
var DEFAULT = Layouts.Normalize(null).Json;
LayoutItem Item(JsonNode? l, string id) => Layouts.Normalize(l).Item(id)!;
List<string> Ids(JsonNode? l) => Layouts.Visible(l).Select(i => i.Id).ToList();
void NoOverlap(JsonNode? l)
{
    var on = Layouts.Normalize(l).Items.Where(i => i.On).ToList();
    for (int i = 0; i < on.Count; i++) for (int j = i + 1; j < on.Count; j++)
        Ok(!Layouts.Overlaps((on[i].Col, on[i].Row, on[i].W, on[i].H), (on[j].Col, on[j].Row, on[j].W, on[j].H)), $"{on[i].Id} 和 {on[j].Id} 重叠了");
}
int[] Pos(Layout l, string id) { var i = l.Item(id)!; return new[] { i.Col, i.Row }; }
double Utc(int y, int m, int d, int h, int mi) => new DateTimeOffset(y, m, d, h, mi, 0, TimeSpan.Zero).ToUnixTimeMilliseconds();

var FULL = J("""{"version":4,"items":[{"id":"clock","on":true,"col":0,"row":0,"size":"M"},{"id":"butler","on":true,"col":2,"row":0,"size":"W"},{"id":"weather","on":true,"col":6,"row":0,"size":"M"},{"id":"market","on":true,"col":0,"row":1,"size":"T"},{"id":"calendar","on":true,"col":2,"row":1,"size":"T"},{"id":"mail","on":true,"col":4,"row":1,"size":"T"},{"id":"news","on":true,"col":6,"row":1,"size":"T"}]}""");

// —— 布局 ——
Test("每个组件的默认档位都在它允许的档位里", () =>
{
    foreach (var w in Layouts.Widgets) { Ok(w.Sizes.Contains(w.Size), w.Id); foreach (var s in w.Sizes) Ok(Layouts.Sizes.ContainsKey(s), w.Id + s); }
});
Test("默认布局合法；中间留空，左右两列各自铺满 4 行", () =>
{
    var l = Layouts.Normalize(DEFAULT);
    Eq(l.Items.Count, Layouts.Widgets.Length);
    NoOverlap(DEFAULT);
    EqL(Pos(l, "clock"), new[] { 0, 0 }); EqL(Pos(l, "calendar"), new[] { 6, 1 }); EqL(Pos(l, "mail"), new[] { 6, 3 });
    var cells = Layouts.Normalize(DEFAULT).Items.Where(i => i.On).ToList();
    foreach (var (lo, hi) in new[] { (0, 1), (6, 7) })
        Eq(cells.Where(c => c.Col >= lo && c.Col + c.W - 1 <= hi).Sum(c => c.W * c.H), 2 * DeskGrid.Rows, "一列没有铺满 4 行");
    Ok(cells.All(c => c.Col + c.W <= 2 || c.Col >= 6), "中间 4 列必须留空");
    Ok(!Ids(DEFAULT).Contains("news"), "新闻默认关着");
});
Test("空布局补齐所有组件；存过布局后新出现的组件默认关着", () =>
{
    Eq(Layouts.Normalize(null).Item("butler")!.On, true);
    Eq(Layouts.Normalize(J("""{"version":4,"items":[{"id":"clock","col":0,"row":0,"size":"M"}]}""")).Item("mail")!.On, false);
});
Test("档位决定宽高；不允许的档位退回默认档；越界夹回", () =>
{
    Eq(Item(DEFAULT, "market").H, 2);
    Eq(Layouts.Dims("calendar", "S").size, "L");
    var b = Item(J("""{"version":4,"items":[{"id":"butler","col":99,"row":-5,"size":"W"}]}"""), "butler");
    Eq(b.Col, DeskGrid.Cols - 4); Eq(b.Row, 0);
});
Test("拖动撞到别人：被撞的就近让开；挪走之后自动回到原位", () =>
{
    var dragged = Layouts.Move(DEFAULT, "weather", 0, 0);
    EqL(Pos(dragged, "weather"), new[] { 0, 0 });
    NoOverlap(dragged.Json);
    var c = dragged.Item("clock")!;
    Ok(!(c.Col == 0 && c.Row == 0)); Ok(c.Row + c.H <= DeskGrid.Rows);
    var back = Layouts.Move(dragged.Json, "weather", 6, 0);
    EqL(Pos(back, "clock"), new[] { 0, 0 }, "时钟自动回到原位");
    Eq(Layouts.Move(DEFAULT, "weather", 99, 0).Item("weather")!.Col, DeskGrid.Cols - 2);
});
Test("换档：只能换允许的；放大挤到别人，缩回去全部复位", () =>
{
    Eq(Layouts.SetSize(DEFAULT, "market", "M").Item("market")!.Size, "M");
    Eq(Layouts.SetSize(DEFAULT, "calendar", "S").Item("calendar")!.Size, "L");
    var before = Layouts.Normalize(DEFAULT).Items.Where(i => i.On).Select(i => $"{i.Id}@{i.Col},{i.Row}").ToList();
    var big = Layouts.SetSize(DEFAULT, "butler", "L");
    NoOverlap(big.Json);
    foreach (var it in big.Items.Where(i => i.On)) Ok(it.Row + it.H <= DeskGrid.Rows, it.Id + " 被挤出屏幕");
    var wide = Layouts.SetSize(big.Json, "butler", "W");
    NoOverlap(wide.Json);
    var small = Layouts.SetSize(wide.Json, "butler", "M");
    EqL(small.Items.Where(i => i.On).Select(i => $"{i.Id}@{i.Col},{i.Row}"), before, "缩回去之后都回到原位");
    var L2 = Layouts.SetSize(Layouts.Move(DEFAULT, "butler", 6, 0).Json, "butler", "W");
    Eq(L2.Item("butler")!.Col, DeskGrid.Cols - 4);
});
Test("开关组件；一屏铺满时把「高」收成「大」", () =>
{
    var l = Layouts.Toggle(DEFAULT, "market", false);
    Ok(!Ids(l.Json).Contains("market"));
    Ok(Ids(Layouts.Toggle(l.Json, "market", true).Json).Contains("market"));
    var f = Layouts.Toggle(FULL, "worldclock", true);
    Eq(f.Item("worldclock")!.On, true); Eq(f.Item("market")!.Size, "L");
    NoOverlap(f.Json);
    var m = Layouts.Normalize(DEFAULT);
    foreach (var id in new[] { "news", "worldclock", "risk" }) m = Layouts.Toggle(m.Json, id, true);
    NoOverlap(Layouts.SetSize(m.Json, "news", "T").Json);
});
Test("同一种组件加好几个", () =>
{
    var a = Layouts.AddInstance(DEFAULT, "market");
    Eq(a.id, "market-2");
    var it = a.layout.Item("market-2")!;
    Eq(it.Type, "market"); Eq(it.On, true);
    var b = Layouts.AddInstance(a.layout.Json, "market");
    Eq(b.id, "market-3");
    Eq(Layouts.Normalize(b.layout.Json).Items.Count(i => i.Type == "market"), 3);
    Eq(Layouts.AddInstance(DEFAULT, "clock").id, null);
    var r = Layouts.RemoveInstance(b.layout.Json, "market-2");
    Ok(r.Item("market-2") == null); Ok(r.Item("market-3") != null);
    Eq(Layouts.RemoveInstance(DEFAULT, "market").Item("market")!.On, false);
    Eq(Layouts.TypeOf("market-12"), "market"); Eq(Layouts.TypeOf("clock-2"), "clock");
    Ok(Layouts.Normalize(J("""{"version":4,"items":[{"id":"clock-2","on":true}]}""")).Item("clock-2") == null);
});
Test("四种身份的默认布局：合法、不重叠、中间留空", () =>
{
    foreach (var p in new[] { "student", "work", "invest", "minimal" })
    {
        var l = Layouts.PresetLayout(p);
        NoOverlap(l);
        Ok(Layouts.Visible(l).All(c => c.Col + c.W <= 2 || c.Col >= 6), p);
    }
});
Test("旧版布局：位置回到默认，但开关和名字保留；垃圾输入不崩", () =>
{
    var old = Layouts.Normalize(J("""{"version":2,"items":[{"id":"market","on":false,"col":7,"row":9,"size":"L","name":"自选"}]}"""));
    Eq(old.Item("market")!.On, false); Eq(old.Item("market")!.Name, "自选"); Eq(old.Item("market")!.Col, 0);
    Layouts.Normalize(JsonNode.Parse("[1,2]")); Layouts.Normalize(J("""{"items":[null,1,"x",{"id":5}]}"""));
});
Test("像素换算往返一致", () =>
{
    var r = Layouts.ToRect(3, 2, 2, 1, 1920, 1080);
    var p = Layouts.FromPoint(r.Left, r.Top, 1920, 1080);
    Eq(p.col, 3); Eq(p.row, 2);
    var m = Layouts.MetricsFor(1920, 1080);
    Eq(Math.Round(4 * m.RowH + 5 * m.Gap), 1080.0);
});

// —— 行情 ——
const string SINA = """
var hq_str_sz002185="华天科技,14.000,13.890,14.230,14.490,14.000,14.230,14.240,112339964,1601173477.050,117200,14.230,323500,14.220,342400,14.210,895400,14.200,86800,14.190,2900,14.240,80400,14.250,83200,14.260,89300,14.270,64000,14.280,2026-10-20,13:31:12,00";
var hq_str_rt_hkHSI="HSI,恒生指数,23990.050,24186.830,24035.000,23868.230,23909.631,-277.200,-1.150,0.000,0.000,117530825.755,6281236678,0.000,0.000,28056.100,22518.000,2026/10/20,13:31:13,,,,,,";
var hq_str_gb_aapl="苹果,342.9400,-0.15,2026-10-20 07:59:42,-0.5200,340.7750,346.0000,340.1150,348.1500,242.8900,34666420,38687021";
var hq_str_sh600000="";
""";
Test("代码识别：A 股按首位分沪深，港股补 0，美股小写，中文别名", () =>
{
    Eq(Market.ToSinaKey("600519"), "sh600519"); Eq(Market.ToSinaKey("002185"), "sz002185"); Eq(Market.ToSinaKey("830799"), "bj830799");
    Eq(Market.ToSinaKey("700"), "rt_hk00700"); Eq(Market.ToSinaKey("00700.HK"), "rt_hk00700"); Eq(Market.ToSinaKey("AAPL"), "gb_aapl");
    Eq(Market.ToSinaKey("BRK.B"), "gb_brk$b"); Eq(Market.ToSinaKey("恒指"), "rt_hkHSI"); Eq(Market.ToSinaKey(""), null); Eq(Market.ToSinaKey("？？"), null);
    Eq(Market.DisplayCode("gb_brk$b"), "BRK.B");
});
Test("解析新浪三种市场的返回", () =>
{
    var raw = Market.SplitResponse(SINA);
    var a = Market.ParseQuote("sz002185", raw["sz002185"]);
    Eq(a.Name, "华天科技"); Eq(a.Price, 14.23); Eq(a.Prev, 13.89); Eq(a.Pct, 2.45); Eq(a.Ts, Market.BjToMs("2026-10-20", "13:31:12"));
    var h = Market.ParseQuote("rt_hkHSI", raw["rt_hkHSI"]);
    Eq(h.Name, "恒生指数"); Eq(h.Price, 23909.631); Eq(h.Pct, -1.15); Eq(h.Index, true);
    var u = Market.ParseQuote("gb_aapl", raw["gb_aapl"]);
    Eq(u.Price, 342.94); Eq(u.Prev, 343.46); Eq(u.Pct, -0.15);
    bool threw = false; try { Market.ParseQuote("sh600000", raw["sh600000"]); } catch (Market.ParseError) { threw = true; }
    Ok(threw);
    var q = Market.ParseQuote("sh600000", "浦发银行,0.000,10.00,0.000,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,2026-10-20,09:10:00,00");
    Eq(q.Price, 10.0); Eq(q.Pct, 0.0);
});
Test("交易时段：按各市场自己的时区判断", () =>
{
    var ms = Utc(2026, 10, 20, 5, 31);
    Eq(Market.IsOpen("cn", ms), true); Eq(Market.IsOpen("hk", ms), true); Eq(Market.IsOpen("us", ms), false);
    Eq(Market.IsOpen("cn", Utc(2026, 10, 20, 4, 0)), false);
    Eq(Market.IsOpen("us", Utc(2026, 10, 20, 14, 0)), true);
    Eq(Market.IsOpen("cn", Utc(2026, 10, 24, 2, 0)), false);
    Eq(Market.QuoteStatus(new Quote { Market = "cn", Ts = ms - 60e3 }, ms), "live");
    Eq(Market.QuoteStatus(new Quote { Market = "cn", Ts = ms - 3600e3 }, ms), "stale");
    Eq(Market.QuoteStatus(new Quote { Market = "us", Ts = ms }, ms), "closed");
    Eq(Market.QuoteStatus(new Quote { Market = "cn", Failed = true }, ms), "fail");
});
Test("涨跌提醒：超过阈值才提醒，同一天不重复", () =>
{
    var memo = new HashSet<string>();
    var qs = new[] { new Quote { Key = "sz002185", Code = "002185", Market = "cn", Name = "华天科技", Price = 14.8, Pct = 4.2 }, new Quote { Key = "gb_aapl", Code = "AAPL", Name = "苹果", Price = 300, Pct = -1 } };
    var a = Market.CheckAlerts(qs, 3, memo, "d1");
    Eq(a.Count, 1); Ok(a[0].title.Test("华天科技.*涨幅 4\\.20%"), a[0].title);
    Eq(Market.CheckAlerts(qs, 3, memo, "d1").Count, 0);
    Eq(Market.CheckAlerts(qs, 3, memo, "d2").Count, 1);
});

// —— 新闻 ——
Test("解析 RSS，跳过没有链接或时间的条目；guid、dc:date；Atom", () =>
{
    var xml = """
    <rss><channel><item><title><![CDATA[港股下午初段跌逾1%]]></title><link>https://news.rthk.hk/a.htm</link><description><![CDATA[港股下午開市初段跌逾1%。

    編輯：宋家樑]]></description><pubDate>Tue, 20 Oct 2026 13:18:55 +0800</pubDate></item>
    <item><title>無連結</title><pubDate>Tue, 20 Oct 2026 13:00:00 +0800</pubDate></item>
    <item><title>較早 &amp; 新聞</title><link>https://news.rthk.hk/b.htm</link><pubDate>Tue, 20 Oct 2026 11:00:00 GMT</pubDate></item></channel></rss>
    """;
    var items = News.ParseRss(xml, "财经");
    Eq(items.Count, 2);
    Eq(items[0].Desc, "港股下午開市初段跌逾1%。");
    Eq(items[1].Title, "較早 & 新聞");
    Eq(items[0].Ts, Utc(2026, 10, 20, 5, 18) + 55e3);
    var x2 = """
    <rss><channel>
    <item><title>甲</title><guid>https://a.com/1</guid><pubDate>Tue, 20 Oct 2026 13:18:55 +0800</pubDate></item>
    <item><title>乙</title><link>https://a.com/2</link><dc:date>2026-10-20T10:00:00+08:00</dc:date></item>
    <item><title>丙</title><link>not-a-url</link><pubDate>Tue, 20 Oct 2026 13:18:55 +0800</pubDate></item>
    </channel></rss>
    """;
    EqL(News.ParseRss(x2, "科技", "少数派").Select(i => i.Title), new[] { "甲", "乙" });
    var atom = "<feed><title>我的博客</title><entry><title>新文章</title><link href=\"https://a.com/1\"/><updated>2026-10-20T10:00:00Z</updated></entry></feed>";
    Eq(News.ParseFeed(atom, "x").FirstOrDefault()?.Title, "新文章"); Eq(News.FeedTitle(atom), "我的博客");
    var ids = News.Sources.Select(s => s.Id).ToList();
    Eq(ids.Distinct().Count(), ids.Count);
    Eq(News.Pick(new[] { "nope" }).Count, News.DefaultIds.Count);
});

// —— 其它数据源 ——
Test("天气、加密货币、GitHub、倒数日、汇率", () =>
{
    Eq(WeatherApi.Describe(63).text, "中雨"); Eq(WeatherApi.Describe(0, 0).icon, "moon");
    var w = WeatherApi.Parse(J("""{"current":{"temperature_2m":21.6,"apparent_temperature":20,"relative_humidity_2m":60,"weather_code":61,"is_day":1,"wind_speed_10m":10},"daily":{"time":["2026-10-22"],"weather_code":[3],"temperature_2m_max":[24.4],"temperature_2m_min":[15],"precipitation_probability_max":[70]}}"""), "上海");
    Eq(w!.Now.Temp, 22); Eq(w.Days[0].Rain, 70); Eq(w.Now.Text, "小雨");
    Eq(Crypto.Id("BTC"), "bitcoin"); Eq(Crypto.Id("比特币"), "bitcoin");
    var q = Crypto.Parse(J("""{"bitcoin":{"usd":67000.5,"usd_24h_change":-1.2}}"""), new[] { "bitcoin", "ethereum" }, "usd");
    Eq(q.Count, 1); Eq(q[0], new CoinQuote("bitcoin", 67000.5, -1.2));
    Eq(GitHubApi.ParseRepo(J("""{"full_name":"a/b","stargazers_count":12}"""))!.Stars, 12);
    Eq(GitHubApi.TotalDownloads(JsonNode.Parse("""[{"assets":[{"download_count":5},{"download_count":7}]},{"assets":[{"download_count":1}]}]""")), 13);
    Eq(Countdown.Days("2026-12-25", U.LocalMs(2026, 10, 22, 15)), 64); Eq(Countdown.Days("2026-10-20", U.LocalMs(2026, 10, 22)), -2); Eq(Countdown.Days("x"), null);
    Eq(FX.Parse(J("""{"result":"success","rates":{"CNY":7.1},"time_last_update_unix":100}"""))!.Value.rates["CNY"], 7.1);
    Eq(MailProviders.Guess("a@qq.com"), "qq"); Eq(MailProviders.Guess("x@outlook.com"), "outlook"); Eq(MailProviders.By("nope").Id, "gmail");
    Eq(MailProviders.ParseSender("\"张三\" <a@b.com>"), ("张三", "a@b.com"));
});
Test("检查更新：版本号比大小、跳过、草稿不算", () =>
{
    Eq(Update.Compare("0.4.10", "0.4.9"), 1); Eq(Update.Compare("v0.4.0", "0.4"), 0); Eq(Update.Compare("0.4.0", "0.5.0"), -1); Eq(Update.Compare("1.0.0-beta", "1.0.0"), 0);
    var r = Update.Parse(J("""{"tag_name":"v0.5.0","html_url":"https://x","body":"新功能"}"""));
    Eq(r!.Version, "0.5.0");
    Ok(Update.Newer(r, "0.4.1", null) != null); Ok(Update.Newer(r, "0.5.0", null) == null); Ok(Update.Newer(r, "0.4.1", "0.5.0") == null);
    Ok(Update.Parse(J("""{"tag_name":"v9","draft":true}""")) == null);
});

// —— 日历 ——
Test("日历订阅：单次、全天、每周重复（BYDAY + COUNT）、删掉的那次、改过的那次", () =>
{
    var ics = "BEGIN:VCALENDAR\nBEGIN:VEVENT\nUID:a\nSUMMARY:组会\\, 第三周\nDTSTART:20261020T130000Z\nDTEND:20261020T140000Z\nEND:VEVENT\n" +
              "BEGIN:VEVENT\nUID:b\nSUMMARY:国庆\nDTSTART;VALUE=DATE:20261001\nDTEND;VALUE=DATE:20261008\nEND:VEVENT\n" +
              "BEGIN:VEVENT\nUID:c\nSUMMARY:宏观经济\nDTSTART;TZID=America/New_York:20261019T101000\nDURATION:PT50M\nRRULE:FREQ=WEEKLY;BYDAY=MO,WE,FR;COUNT=6\nEXDATE;TZID=America/New_York:20261021T101000\nEND:VEVENT\n" +
              "BEGIN:VEVENT\nUID:c\nRECURRENCE-ID;TZID=America/New_York:20261023T101000\nSUMMARY:宏观经济（改到下午）\nDTSTART;TZID=America/New_York:20261023T150000\nDTEND;TZID=America/New_York:20261023T155000\nEND:VEVENT\nEND:VCALENDAR";
    var evs = ICS.Parse(ics, U.LocalMs(2026, 9, 25), U.LocalMs(2026, 11, 30), "课表");
    var a = evs.First(e => e.Title.StartsWith("组会"));
    Eq(a.Title, "组会, 第三周"); Eq(a.End - a.Start, 3600e3);
    Ok(evs.First(e => e.Title == "国庆").AllDay);
    var macro = evs.Where(e => e.Title.StartsWith("宏观经济")).ToList();
    Eq(macro.Count, 5, "6 次里删掉 1 次");
    Eq(macro.Count(e => e.Title.Contains("改到下午")), 1);
    Eq(macro[0].End - macro[0].Start, 50 * 60e3);
    Eq(macro[0].Start, Utc(2026, 10, 19, 14, 10), "纽约 10:10 = UTC 14:10（夏令时）");
    Eq(ICS.ParseDuration("P1DT2H"), (86400 + 7200) * 1000.0);
    Ok(ICS.Url("webcal://p01.example.com/a.ics").StartsWith("https://"));
    // 跨夏令时：11 月 2 日之后纽约 10:10 = UTC 15:10
    var daily = "BEGIN:VEVENT\nUID:d\nSUMMARY:晨会\nDTSTART;TZID=America/New_York:20261030T101000\nRRULE:FREQ=DAILY;COUNT=5\nEND:VEVENT";
    var ds = ICS.Parse(daily, U.LocalMs(2026, 10, 1), U.LocalMs(2026, 12, 1), "x");
    Eq(ds.Count, 5); Eq(ds[^1].Start, Utc(2026, 11, 3, 15, 10));
});
Test("农历和节日", () =>
{
    Eq(Lunar.Text(U.LocalMs(2027, 2, 6, 12)), "正月初一");
    Eq(Lunar.Festival(U.LocalMs(2027, 2, 6, 12)), "春节");
    Eq(Lunar.Festival(U.LocalMs(2027, 2, 5, 12)), "除夕");
    Eq(Lunar.Festival(U.LocalMs(2026, 9, 25, 12)), "中秋节");
    Eq(Lunar.Festival(U.LocalMs(2026, 4, 5, 12)), "清明");
    Eq(Lunar.Next(U.LocalMs(2026, 9, 20, 12))?.name, "中秋节"); Eq(Lunar.Next(U.LocalMs(2026, 9, 20, 12))?.days, 5);
    Eq(Lunar.Text(U.LocalMs(2026, 10, 22, 12)), "九月十三");
    Eq(Lunar.Text(U.LocalMs(2025, 8, 1, 12)), "闰六月初八");
});

// —— 管家 ——
Test("管家：马上开始的日程最前；重要的人来信；带伞；没事时问好", () =>
{
    var now = U.LocalMs(2026, 10, 22, 9, 50);
    var x = new ButlerInputs
    {
        Now = now,
        Events = new() { new CalEvent("1", "组会", now + 10 * 60e3, now + 70 * 60e3, false, "", "") },
        Mail = new MailState { Ok = true, Unread = 3, Items = new() { new MailItem("导师", "prof@school.edu", "论文", now, "1", "Gmail") } },
        Contacts = new() { "prof@" },
        Weather = new Weather("x", now, new WxNow(1, 1, 1, 1, "", ""), new() { new WxDay("d", 1, 1, 80, "", "") }),
        OpenTodos = 2,
    };
    var lines = Butler.Lines(x);
    Eq(lines.Count, 3);
    Ok(lines[0].Text.Contains("10 分钟后"), lines[0].Text);
    Ok(lines[1].Text.Contains("导师"), lines[1].Text);
    Ok(lines[2].Text.Contains("带伞"), lines[2].Text);
    Eq(Butler.Lines(new ButlerInputs { Now = U.LocalMs(2026, 10, 22, 9) }).Count, 0);
});

// —— 多语言 ——
Test("英文界面：查不到翻译显示原文；%@ 依次替换；对照表没有重复键", () =>
{
    Ok(Strings.Count > 700);
    Strings.Lang = "en";
    Eq(L("这句没有翻译"), "这句没有翻译");
    Eq(L("%@ 封未读邮件", 3), "3 unread emails");
    Eq(L("今天降水概率 %@%%，记得带伞", 80), "80% chance of rain today, take an umbrella");
    Eq(Layouts.Def("weather")!.Name, "Weather");
    Strings.Lang = "zh";
    Eq(L("%@ 封未读邮件", 3), "3 封未读邮件");
});

// —— 设置存储 ——
Test("设置存储：读写同一个 desk.json，不认识的键原样保留", () =>
{
    var p = Path.Combine(Path.GetTempPath(), "deskhub-test-" + Guid.NewGuid().ToString("N"), "desk.json");
    Directory.CreateDirectory(Path.GetDirectoryName(p)!);
    File.WriteAllText(p, """{"watch":["sh000001"],"someFutureKey":{"a":1}}""");
    var s = new Store(p);
    EqL(s.Watch, new[] { "sh000001" });
    s.Set("butlerName", "阿福");
    s.SetConfig("market-2", J("""{"keys":["gb_aapl"]}"""));
    var s2 = new Store(p);
    Eq(s2.ButlerName, "阿福"); Eq(U.Num(s2.Data["someFutureKey"]?["a"]), 1.0);
    EqL(U.Strs(s2.Config("market-2")["keys"]), new[] { "gb_aapl" });
    Eq(s2.City.name, "上海");
    Directory.Delete(Path.GetDirectoryName(p)!, true);
});

Console.WriteLine($"通过 {pass} 项，失败 {fail} 项");
return fail == 0 ? 0 : 1;
