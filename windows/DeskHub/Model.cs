// 数据中心：所有组件的数据都在这里取、在这里存；每秒走一次的调度器决定什么时候刷新什么。
// 只刷新桌面上真的摆着的组件要用的数据（没摆行情就不去请求行情）。
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json.Nodes;
using System.Threading.Tasks;
using System.Windows.Threading;
using DeskHub.Core;
using static DeskHub.Core.I18n;

namespace DeskHub;

public class Model
{
    public readonly Store Store;
    public Palette Pal = null!;
    /** 改了什么：sec / min / quotes / news / weather / calendar / mail / crypto / github / feeds / fx / sys / media / config / layout / theme / lang / pomo / update */
    public event Action<HashSet<string>>? Changed;

    public Dictionary<string, Quote> Quotes = new();
    public List<NewsItem> NewsItems = new();
    public Dictionary<string, Weather> Weathers = new();      // 键 = "纬度,经度"
    public List<CalEvent> Events = new();
    public string? CalError;
    public MailState? Mail;
    public Dictionary<string, CoinQuote> Coins = new();        // 键 = "币,计价"
    public Dictionary<string, RepoInfo> Repos = new();
    public Dictionary<string, (string title, List<NewsItem> items)> Feeds = new();   // 键 = 地址
    public Dictionary<string, (Dictionary<string, double> rates, double updated)> Rates = new();   // 键 = 基准货币
    public SysStat Sys = new();
    public NowPlaying? Playing;
    public Update.Release? NewVersion;
    public string? LastError;

    // 番茄钟
    public double PomoMinutes = 25;
    public double PomoLeft = 25 * 60;
    public bool PomoRunning;

    readonly SysSampler sampler = new();
    readonly Dictionary<string, DateTime> due = new();
    readonly HashSet<string> busy = new();
    readonly HashSet<string> alertMemo = new();
    readonly HashSet<string> soonMemo = new();
    readonly DispatcherTimer timer = new() { Interval = TimeSpan.FromSeconds(1) };
    int lastMinute = -1;

    public Action<string, string>? Notify;   // (标题, 内容) → 系统通知

    public Model(Store? store = null)
    {
        Store = store ?? new Store();
        Strings.Lang = Store.Lang;
        ApplyTheme();
        Store.Changed += keys =>
        {
            var k = new HashSet<string>();
            if (keys.Contains("widgetConfig")) k.Add("config");
            if (keys.Contains("layout") || keys.Contains("screenLayouts")) { k.Add("layout"); Kick("all"); }
            if (keys.Contains("theme") || keys.Contains("accent") || keys.Contains("colors")) { ApplyTheme(); k.Add("theme"); }
            if (keys.Contains("lang")) { Strings.Lang = Store.Lang; k.Add("lang"); k.Add("theme"); }
            if (keys.Contains("watch")) Kick("quotes");
            if (keys.Contains("newsSources")) Kick("news");
            if (keys.Contains("city")) Kick("weather");
            if (keys.Contains("calendar")) Kick("calendar");
            if (keys.Contains("mail")) Kick("mail");
            if (keys.Contains("butlerName")) k.Add("config");
            if (keys.Contains("win")) k.Add("dock");
            if (k.Count > 0) Changed?.Invoke(k);
        };
        timer.Tick += (_, _) => Tick();
    }

    public void Start() { Kick("all"); timer.Start(); Tick(); }

    public void ApplyTheme() => Pal = Palette.Make(Store.Theme, Store.Accent, Store.Colors);

    void Raise(params string[] keys) => Changed?.Invoke(new HashSet<string>(keys));

    // —— 现在桌面上摆着哪些组件（所有屏幕合起来） ——
    public List<string> ScreenKeys = new() { "main" };

    public List<LayoutItem> AllVisible() => ScreenKeys.SelectMany(k => Layouts.Visible(Store.LayoutFor(k))).ToList();
    bool Shows(string type) => AllVisible().Any(i => i.Type == type);
    List<LayoutItem> Instances(string type) => AllVisible().Where(i => i.Type == type).ToList();

    public JsonNode? LayoutFor(string key) => Store.LayoutFor(key) ?? (key == "main" ? null : Layouts.PresetLayout("minimal"));
    public void SetLayout(string key, Layout l) => Store.SetLayout(key, l.Json);

    // —— 调度 ——
    public void Kick(string what)
    {
        if (what == "all") { foreach (var k in due.Keys.ToList()) due[k] = DateTime.MinValue; foreach (var k in Jobs) due[k] = DateTime.MinValue; }
        else due[what] = DateTime.MinValue;
    }

    static readonly string[] Jobs = { "quotes", "news", "weather", "calendar", "mail", "crypto", "github", "feeds", "fx", "sys", "media", "update" };

    void Tick()
    {
        var now = DateTime.Now;
        var keys = new HashSet<string> { "sec" };
        if (now.Minute != lastMinute) { lastMinute = now.Minute; keys.Add("min"); CheckSoon(); }
        if (PomoRunning)
        {
            PomoLeft = Math.Max(0, PomoLeft - 1);
            if (PomoLeft == 0) { PomoRunning = false; Notify?.Invoke(L("番茄钟"), L("时间到，休息一下")); }
            keys.Add("pomo");
        }
        Changed?.Invoke(keys);
        foreach (var job in Jobs)
        {
            if (busy.Contains(job)) continue;
            if (due.TryGetValue(job, out var t) && t > now) continue;
            var next = Run(job);
            due[job] = now + next;
        }
    }

    /** 跑一项刷新（异步），返回下次什么时候再跑 */
    TimeSpan Run(string job)
    {
        Func<Task>? work = job switch
        {
            "quotes" when Shows("market") => RefreshQuotes,
            "news" when Shows("news") => RefreshNews,
            "weather" when Shows("weather") || Shows("butler") => RefreshWeather,
            "calendar" when Shows("calendar") || Shows("butler") => RefreshCalendar,
            "mail" when Shows("mail") || Shows("butler") => RefreshMail,
            "crypto" when Shows("crypto") => RefreshCrypto,
            "github" when Shows("github") => RefreshGitHub,
            "feeds" when Shows("rss") => RefreshFeeds,
            "fx" when Shows("fx") => RefreshFx,
            "sys" when Shows("sysstat") => () => { Sys = sampler.Sample(); Raise("sys"); return Task.CompletedTask; },
            "media" when Shows("nowplaying") => RefreshMedia,
            "update" => CheckUpdate,
            _ => null,
        };
        if (work != null)
        {
            busy.Add(job);
            _ = Guard(job, work);
        }
        return job switch
        {
            "quotes" => TimeSpan.FromSeconds(new[] { "cn", "hk", "us" }.Any(m => Market.IsOpen(m)) ? 15 : 300),
            "news" => TimeSpan.FromMinutes(10),
            "weather" => TimeSpan.FromMinutes(15),
            "calendar" => TimeSpan.FromMinutes(15),
            "mail" => TimeSpan.FromMinutes(3),
            "crypto" => TimeSpan.FromMinutes(2),
            "github" => TimeSpan.FromMinutes(30),
            "feeds" => TimeSpan.FromMinutes(15),
            "fx" => TimeSpan.FromHours(1),
            "sys" => TimeSpan.FromSeconds(2),
            "media" => TimeSpan.FromSeconds(2),
            "update" => TimeSpan.FromHours(24),
            _ => TimeSpan.FromMinutes(5),
        };
    }

    async Task Guard(string job, Func<Task> work)
    {
        try { await work(); }
        catch (Exception e) { LastError = $"{job}: {e.Message}"; }
        finally { busy.Remove(job); }
    }

    // —— 各项数据 ——
    public List<string> MarketKeys(string id)
    {
        var keys = U.Strs(Store.Config(id)["keys"]);
        return keys.Count > 0 ? keys : Store.Watch;
    }

    async Task RefreshQuotes()
    {
        var keys = Instances("market").SelectMany(i => MarketKeys(i.Id)).Distinct().ToList();
        if (keys.Count == 0) return;
        var text = await Net.Text("https://hq.sinajs.cn/list=" + string.Join(",", keys), "https://finance.sina.com.cn", Net.Gbk);
        var raw = Market.SplitResponse(text);
        foreach (var k in keys)
        {
            try { Quotes[k] = Market.ParseQuote(k, raw.GetValueOrDefault(k, "")); }
            catch { if (!Quotes.ContainsKey(k)) Quotes[k] = new Quote { Key = k, Code = Market.DisplayCode(k), Market = Market.MarketOf(k), Name = Market.DisplayCode(k), Failed = true }; }
        }
        var day = DateTime.Now.ToString("yyyy-MM-dd");
        foreach (var (t, b) in Market.CheckAlerts(keys.Where(Quotes.ContainsKey).Select(k => Quotes[k]), Store.AlertPct, alertMemo, day)) Notify?.Invoke(t, b);
        Raise("quotes");
    }

    async Task RefreshNews()
    {
        var lists = new List<List<NewsItem>>();
        var tasks = News.Pick(Store.NewsSources).SelectMany(s => s.Feeds.Select(f => (s, f))).Select(async x =>
        {
            try
            {
                var xml = await Net.Text(x.f.Url);
                var items = News.ParseRss(xml, x.f.Tag, x.s.Name).Take(News.PerFeed).ToList();
                if (x.s.T2s) items = items.Select(i => i with { Title = Native.T2S(i.Title), Desc = Native.T2S(i.Desc) }).ToList();
                lock (lists) lists.Add(items);
            }
            catch { }
        });
        await Task.WhenAll(tasks);
        if (lists.Count == 0) return;
        NewsItems = News.Merge(lists).Take(80).ToList();
        Raise("news");
    }

    public (string name, double lat, double lon) CityFor(string id)
    {
        if (Store.Config(id)["city"] is JsonObject c && U.Num(c["lat"]) is double lat && U.Num(c["lon"]) is double lon) return (U.Str(c["name"]) ?? "", lat, lon);
        return Store.City;
    }
    public static string CityKey((string name, double lat, double lon) c) => $"{c.lat:0.###},{c.lon:0.###}";

    async Task RefreshWeather()
    {
        var cities = Instances("weather").Select(i => CityFor(i.Id)).Append(Store.City).GroupBy(CityKey).Select(g => g.First()).ToList();
        foreach (var c in cities)
        {
            var j = await Net.Json(WeatherApi.Url(c.lat, c.lon));
            if (WeatherApi.Parse(j, c.name) is Weather w) Weathers[CityKey(c)] = w;
        }
        Raise("weather");
    }

    async Task RefreshCalendar()
    {
        var subs = Store.IcsList;
        var t = U.Ymd(U.NowMs());
        double from = U.LocalMs(t.Y, t.M - 1, 1), to = U.LocalMs(t.Y, t.M + 2, 1);
        var all = new List<CalEvent>();
        string? err = null;
        foreach (var (name, url) in subs)
        {
            try { all.AddRange(ICS.Parse(await Net.Text(ICS.Url(url)), from, to, name == "" ? L("订阅日历") : name)); }
            catch (Exception e) { err = L("「%@」读取失败：", name) + e.Message; }
        }
        Events = all.OrderBy(e => e.Start).ToList();
        CalError = subs.Count == 0 ? null : err;
        Raise("calendar");
    }

    async Task RefreshMail()
    {
        var a = ImapMail.From(Store);
        if (a == null) { Mail = null; Raise("mail"); return; }
        Mail = await ImapMail.Unread(a);
        Raise("mail");
    }

    async Task RefreshCrypto()
    {
        foreach (var g in Instances("crypto").Select(i => CryptoCfg(i.Id)).GroupBy(c => c.vs))
        {
            var ids = g.SelectMany(c => c.coins).Distinct().ToList();
            var j = await Net.Json(Crypto.Url(ids, g.Key));
            foreach (var q in Crypto.Parse(j, ids, g.Key)) Coins[q.Id + "," + g.Key] = q;
        }
        Raise("crypto");
    }

    public (List<string> coins, string vs) CryptoCfg(string id)
    {
        var c = Store.Config(id);
        var coins = U.Strs(c["coins"]).Select(Crypto.Id).ToList();
        return (coins.Count > 0 ? coins : new List<string> { "bitcoin", "ethereum", "solana" }, U.Str(c["vs"]) ?? (Strings.En ? "usd" : "cny"));
    }

    public List<string> RepoList(string id)
    {
        var r = U.Strs(Store.Config(id)["repos"]);
        return r.Count > 0 ? r : new List<string> { Update.Repo };
    }

    async Task RefreshGitHub()
    {
        foreach (var r in Instances("github").SelectMany(i => RepoList(i.Id)).Distinct())
        {
            try
            {
                if (GitHubApi.ParseRepo(await Net.Json(GitHubApi.RepoUrl(r))) is RepoInfo info)
                    Repos[r] = info with { Downloads = GitHubApi.TotalDownloads(await Net.Json(GitHubApi.ReleasesUrl(r))) };
            }
            catch { }
        }
        Raise("github");
    }

    async Task RefreshFeeds()
    {
        foreach (var url in Instances("rss").Select(i => U.Str(Store.Config(i.Id)["url"]) ?? "").Where(u => u.StartsWith("http")).Distinct())
        {
            try
            {
                var xml = await Net.Text(url);
                Feeds[url] = (News.FeedTitle(xml) ?? "", News.ParseFeed(xml, "").OrderByDescending(i => i.Ts).Take(30).ToList());
            }
            catch { }
        }
        Raise("feeds");
    }

    public string FxBase(string id) => U.Str(Store.Config(id)["base"]) ?? (Strings.En ? "USD" : "CNY");

    async Task RefreshFx()
    {
        foreach (var b in Instances("fx").Select(i => FxBase(i.Id)).Distinct())
            if (FX.Parse(await Net.Json(FX.Url(b))) is var (rates, upd)) Rates[b] = (rates, upd);
        Raise("fx");
    }

    async Task RefreshMedia()
    {
        Playing = await Media.Current();
        Raise("media");
    }

    public async Task PlayerCommand(string cmd) { await Media.Command(cmd); await Task.Delay(300); await RefreshMedia(); }

    async Task CheckUpdate()
    {
        var r = Update.Parse(await Net.Json(Update.LatestUrl));
        NewVersion = Update.Newer(r, App.Version, U.Str(Store.Win["skipVersion"]));
        if (NewVersion != null && U.Str(Store.Win["notifiedVersion"]) != NewVersion.Version)
        {
            Store.SetWin("notifiedVersion", NewVersion.Version);
            Notify?.Invoke(L("一瞥有新版本"), L("%@ 已发布，点开看看更新了什么", NewVersion.Version));
        }
        Raise("update");
    }

    public void SkipUpdate() { if (NewVersion != null) { Store.SetWin("skipVersion", NewVersion.Version); NewVersion = null; Raise("update"); } }

    /** 日程快开始了：提前 N 分钟发一条通知（每个日程只发一次） */
    void CheckSoon()
    {
        var now = U.NowMs();
        foreach (var e in Events.Where(e => !e.AllDay && e.Start > now && e.Start - now <= Store.SoonMin * 60e3))
            if (soonMemo.Add(e.Id)) Notify?.Invoke(e.Title, L("%@ 分钟后开始", (int)Math.Ceiling((e.Start - now) / 60e3)) + (e.Location != "" ? " · " + e.Location : ""));
    }

    // —— 待办（存在组件自己的设置里） ——
    public List<TodoItem> Todos(string id) =>
        (Store.Config(id)["items"] as JsonArray ?? new JsonArray()).Select(x => new TodoItem
        {
            Id = U.Str(x?["id"]) ?? Guid.NewGuid().ToString("N")[..8], Title = U.Str(x?["title"]) ?? "", Done = U.Bool(x?["done"]) == true, Due = U.Str(x?["due"]) ?? "",
        }).ToList();

    public void SaveTodos(string id, List<TodoItem> items)
    {
        var c = Store.Config(id);
        c["items"] = new JsonArray(items.Select(t => (JsonNode)new JsonObject { ["id"] = t.Id, ["title"] = t.Title, ["done"] = t.Done, ["due"] = t.Due }).ToArray());
        Store.SetConfig(id, c);
    }

    public int OpenTodos => Instances("todo").Sum(i => Todos(i.Id).Count(t => !t.Done));

    // —— 番茄钟 ——
    public void PomoToggle() { if (PomoLeft <= 0) PomoLeft = PomoMinutes * 60; PomoRunning = !PomoRunning; Raise("pomo"); }
    public void PomoReset(double? minutes = null) { if (minutes != null) PomoMinutes = minutes.Value; PomoRunning = false; PomoLeft = PomoMinutes * 60; Raise("pomo"); }

    // —— 管家 ——
    public ButlerInputs ButlerIn() => new()
    {
        Now = U.NowMs(), Events = Events, Mail = Mail, Contacts = Store.MailContacts,
        Weather = Weathers.GetValueOrDefault(CityKey(Store.City)), OpenTodos = OpenTodos, SoonMin = Store.SoonMin,
    };

    /** 给 AI 的背景：现在几点、天气、接下来的日程、未读邮件的标题、待办 */
    public string AiContext()
    {
        var now = DateTime.Now;
        var lines = new List<string> { $"{L("现在是")} {now:yyyy-MM-dd HH:mm} ({now:dddd})" };
        if (Weathers.GetValueOrDefault(CityKey(Store.City)) is Weather w)
            lines.Add($"{L("天气")}：{w.City} {w.Now.Temp}°C {L(w.Now.Text)}" + (w.Days.FirstOrDefault() is WxDay d ? $"，{d.Min}–{d.Max}°C，{L("降水概率")} {d.Rain}%" : ""));
        var ms = U.NowMs();
        foreach (var e in Events.Where(e => e.End > ms).Take(8)) lines.Add($"{L("日程")}：{U.ToLocal(e.Start):MM-dd HH:mm} {e.Title}");
        if (Mail is { Ok: true } m) { lines.Add($"{L("未读邮件")}：{m.Unread}"); foreach (var i in m.Items.Take(6)) lines.Add($"  - {i.Name}：{i.Subject}"); }
        foreach (var i in Instances("todo")) foreach (var t in Todos(i.Id).Where(t => !t.Done).Take(10)) lines.Add($"{L("待办")}：{t.Title}");
        return string.Join("\n", lines);
    }

    public string AiSystem() => Strings.En
        ? $"You are {Store.ButlerName}, a concise desktop assistant on the user's Windows PC. Use the context below. Only state facts and give practical help; no investment advice. Please answer in English.\n\n{AiContext()}"
        : $"你是用户 Windows 电脑桌面上的助手「{Store.ButlerName}」。回答简短、口语化，只陈述事实、给实用帮助，不给投资建议。下面是用户此刻的情况：\n\n{AiContext()}";

    // —— 照片 ——
    public string PhotoFolder(string id) => U.Str(Store.Config(id)["folder"]) is string f && f != "" ? f : Environment.GetFolderPath(Environment.SpecialFolder.MyPictures);
    readonly Dictionary<string, (string path, DateTime at)> photoPick = new();
    static readonly Random rnd = new();

    public string? Photo(string id, bool next = false)
    {
        if (!next && photoPick.TryGetValue(id, out var p) && (DateTime.Now - p.at).TotalMinutes < 30 && File.Exists(p.path)) return p.path;
        try
        {
            var files = Directory.EnumerateFiles(PhotoFolder(id), "*.*", SearchOption.AllDirectories)
                .Where(f => f.EndsWith(".jpg", StringComparison.OrdinalIgnoreCase) || f.EndsWith(".jpeg", StringComparison.OrdinalIgnoreCase) || f.EndsWith(".png", StringComparison.OrdinalIgnoreCase))
                .Take(2000).ToList();
            if (files.Count == 0) return null;
            var pick = files[rnd.Next(files.Count)];
            photoPick[id] = (pick, DateTime.Now);
            if (next) Raise("config");
            return pick;
        }
        catch { return null; }
    }
}
