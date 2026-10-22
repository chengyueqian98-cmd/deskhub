// 21 种组件的样子。每个组件是一个函数：拿到数据和格子大小，拼出界面。
// 桌面上的只看不点；浮层里的（Interactive）可以点：打开新闻、勾待办、写便签、控制播放……
using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Shapes;
using DeskHub.Core;
using static DeskHub.Core.I18n;

namespace DeskHub;

public record Ctx(Model M, LayoutItem It, double W, double H, bool Interactive)
{
    public Palette P => M.Pal;
    public JsonCfg Cfg => new(M.Store.Config(It.Id));
    public string Title(string dflt) => It.Name != "" ? It.Name : dflt;
}

public record JsonCfg(System.Text.Json.Nodes.JsonObject O)
{
    public string? S(string k) => U.Str(O[k]);
    public double? N(string k) => U.Num(O[k]);
    public List<string> L(string k) => U.Strs(O[k]);
}

static class Widgets
{
    public static Action<MailItem>? OpenMail;

    /** 组件依赖哪些数据：数据一变就重画 */
    public static readonly Dictionary<string, string[]> Deps = new()
    {
        ["clock"] = new[] { "sec" }, ["butler"] = new[] { "min", "calendar", "mail", "weather", "config" }, ["weather"] = new[] { "weather", "config" },
        ["market"] = new[] { "quotes", "config" }, ["calendar"] = new[] { "min", "calendar", "config" }, ["mail"] = new[] { "mail", "config" },
        ["news"] = new[] { "news", "config" }, ["worldclock"] = new[] { "sec", "config" }, ["todo"] = new[] { "config" },
        ["countdown"] = new[] { "min", "config" }, ["crypto"] = new[] { "crypto", "config" }, ["github"] = new[] { "github", "config" },
        ["rss"] = new[] { "feeds", "config" }, ["photo"] = new[] { "config" }, ["pomodoro"] = new[] { "pomo", "config" },
        ["sysstat"] = new[] { "sys" }, ["note"] = new[] { "config" }, ["fx"] = new[] { "fx", "config" }, ["lunar"] = new[] { "min" },
        ["nowplaying"] = new[] { "media", "sec" },
    };

    public static readonly HashSet<string> Configurable = new() { "market", "weather", "worldclock", "news", "countdown", "crypto", "github", "rss", "photo", "pomodoro", "fx", "todo", "note" };

    public static UIElement Build(Ctx c)
    {
        try
        {
            return c.It.Type switch
            {
                "clock" => Clock(c), "butler" => ButlerW(c), "weather" => WeatherW(c), "market" => MarketW(c), "calendar" => CalendarW(c),
                "mail" => MailW(c), "news" => NewsW(c), "worldclock" => WorldClock(c), "todo" => Todo(c), "countdown" => CountdownW(c),
                "crypto" => CryptoW(c), "github" => GitHubW(c), "rss" => Rss(c), "photo" => PhotoW(c), "pomodoro" => Pomodoro(c),
                "sysstat" => SysW(c), "note" => NoteW(c), "fx" => FxW(c), "lunar" => LunarW(c), "nowplaying" => NowPlayingW(c),
                _ => Empty(c, c.It.Type),
            };
        }
        catch (Exception e) { return Empty(c, L("出错了：") + e.Message); }
    }

    // —— 共用的小部件 ——
    static DockPanel Head(Ctx c, string icon, string title, UIElement? right = null)
    {
        var left = UI.H(6, icon == "" ? null : UI.Icon(icon, 12, c.P.Text3), UI.T(title, 12.5, c.P.Text2, FontWeights.SemiBold));
        var d = UI.Row(left, right);
        d.Margin = new Thickness(0, 0, 0, 8);
        return d;
    }

    static UIElement Empty(Ctx c, string text) => new TextBlock
    {
        Text = text, Foreground = c.P.Text3, FontSize = 12.5, FontFamily = UI.Font, TextWrapping = TextWrapping.Wrap,
        HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center, TextAlignment = TextAlignment.Center, Margin = new Thickness(6),
    };

    static Grid Stack(Ctx c, DockPanel head, UIElement body)
    {
        var g = new Grid();
        g.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        g.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
        Grid.SetRow(body, 1);
        g.Children.Add(head); g.Children.Add(body);
        return g;
    }

    static int Fit(double avail, double rowH) => Math.Max(1, (int)Math.Floor(avail / rowH));
    static double Body(Ctx c) => c.H - 30;

    static void Clickable(FrameworkElement e, Ctx c, Action act)
    {
        if (!c.Interactive) return;
        e.Cursor = Cursors.Hand;
        e.MouseLeftButtonUp += (_, ev) => { act(); ev.Handled = true; };
    }

    static string Hm(double ms) => U.ToLocal(ms).ToString("HH:mm");
    static string Rel(double ms)
    {
        var mins = (U.NowMs() - ms) / 60000;
        if (mins < 1) return L("刚刚");
        if (mins < 60) return L("%@ 分钟前", (int)mins);
        if (mins < 24 * 60) return L("%@ 小时前", (int)(mins / 60));
        return U.ToLocal(ms).ToString(Strings.En ? "MMM d" : "M月d日", Strings.En ? CultureInfo.GetCultureInfo("en-US") : CultureInfo.GetCultureInfo("zh-CN"));
    }

    static CultureInfo Culture => Strings.En ? CultureInfo.GetCultureInfo("en-US") : CultureInfo.GetCultureInfo("zh-CN");

    // —— 时钟 ——
    static UIElement Clock(Ctx c)
    {
        var now = DateTime.Now;
        var small = c.It.Size == "S";
        var date = Strings.En ? now.ToString("dddd, MMM d", Culture) : now.ToString("M月d日 dddd", Culture) + "  " + Lunar.Text(U.NowMs());
        return UI.V(2,
            UI.T(now.ToString("HH:mm"), small ? 40 : 56, c.P.Text, FontWeights.Light, UI.Num),
            UI.T(date, small ? 12 : 14, c.P.Text2));
    }

    // —— 管家 ——
    static UIElement ButlerW(Ctx c)
    {
        var x = c.M.ButlerIn();
        var lines = Butler.Lines(x, c.It.Size == "M" || c.It.Size == "W" ? 2 : 4);
        var p = new StackPanel();
        p.Children.Add(UI.T(Butler.Greeting(x.Now) + (lines.Count == 0 ? L("，今天没什么要紧的") : ""), 17, c.P.Text, FontWeights.SemiBold));
        foreach (var l in lines)
        {
            var glyph = l.Icon switch { "calendar" => G.Calendar, "mail" => G.Mail, "umbrella" => G.Umbrella, "gift" => G.Gift, "check" => G.Check, _ => G.More };
            var row = UI.H(8, UI.Icon(glyph, 12, c.P.AccentB), UI.T(l.Text, 13, c.P.Text2));
            row.Margin = new Thickness(0, 6, 0, 0);
            p.Children.Add(row);
        }
        return Stack(c, Head(c, G.Person, c.Title(c.M.Store.ButlerName)), p);
    }

    // —— 天气 ——
    static string WxGlyph(string icon) => icon switch
    {
        "sun" => "☀", "moon" => "☾", "sun-cloud" => "⛅", "moon-cloud" => "☁", "cloud" => "☁", "fog" => "≋", "rain" => "☂", "snow" => "❄", "storm" => "⚡", _ => "☁",
    };

    static UIElement WeatherW(Ctx c)
    {
        var city = c.M.CityFor(c.It.Id);
        if (!c.M.Weathers.TryGetValue(Model.CityKey(city), out var w)) return Stack(c, Head(c, "", c.Title(city.name)), Empty(c, L("加载中…")));
        var today = w.Days.FirstOrDefault();
        var main = UI.V(0,
            UI.H(10, UI.T(WxGlyph(w.Now.Icon), 30, c.P.Text), UI.T($"{w.Now.Temp}°", 40, c.P.Text, FontWeights.Light, UI.Num)),
            UI.T(L(w.Now.Text) + (today != null ? $"  {today.Max}° / {today.Min}°" : ""), 13, c.P.Text2));
        var cityName = w.City == "" ? city.name : w.City;
        if (c.It.Size == "S") return Stack(c, Head(c, "", c.Title(cityName)), main);
        var days = new StackPanel { Margin = new Thickness(14, 0, 0, 0), VerticalAlignment = VerticalAlignment.Center };
        foreach (var d in w.Days.Skip(1).Take(3))
        {
            var dt = DateTime.ParseExact(d.Date, "yyyy-MM-dd", CultureInfo.InvariantCulture);
            days.Children.Add(UI.H(8, UI.T(dt.ToString(Strings.En ? "ddd" : "ddd", Culture), 12, c.P.Text3), UI.T(WxGlyph(d.Icon), 13, c.P.Text2), UI.T($"{d.Max}°/{d.Min}°", 12, c.P.Text2, null, UI.Num)));
        }
        var g = new Grid();
        g.ColumnDefinitions.Add(new ColumnDefinition());
        g.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        Grid.SetColumn(days, 1);
        g.Children.Add(main); g.Children.Add(days);
        return Stack(c, Head(c, "", c.Title(cityName)), g);
    }

    // —— 行情 ——
    static string Price(double? v) => v is double x ? (x >= 1000 ? x.ToString("N2", CultureInfo.InvariantCulture) : x.ToString(x >= 1 ? "0.00" : "0.000", CultureInfo.InvariantCulture)) : "—";

    static UIElement MarketW(Ctx c)
    {
        var keys = c.M.MarketKeys(c.It.Id);
        var list = new StackPanel();
        int n = Fit(Body(c), 30);
        foreach (var k in keys.Take(n))
        {
            c.M.Quotes.TryGetValue(k, out var q);
            var pct = q?.Pct;
            var brush = pct > 0 ? c.P.Up : pct < 0 ? c.P.Down : c.P.Text2;
            var chip = new Border
            {
                Background = c.P.Fill, CornerRadius = new CornerRadius(6), Padding = new Thickness(6, 1, 6, 2), Width = 72,
                Child = new TextBlock { Text = pct is double p ? (p > 0 ? "▲ " : p < 0 ? "▼ " : "") + Math.Abs(p).ToString("0.00", CultureInfo.InvariantCulture) + "%" : "—", Foreground = brush, FontSize = 12.5, FontFamily = UI.Num, TextAlignment = TextAlignment.Right },
            };
            var right = UI.H(10, UI.T(Price(q?.Price), 13.5, c.P.Text, FontWeights.Medium, UI.Num), chip);
            var name = UI.T(q?.Name ?? Market.DisplayCode(k), 13.5, c.P.Text);
            list.Children.Add(UI.Row(name, right, 30));
        }
        var open = new[] { "cn", "hk", "us" }.Count(IsOpenAny);
        return Stack(c, Head(c, G.Chart, c.Title(L("行情")), UI.T(open > 0 ? L("交易中") : L("已收盘"), 11, c.P.Text3)), keys.Count == 0 ? Empty(c, L("在设置里加自选")) : list);
    }

    static bool IsOpenAny(string m) => Market.IsOpen(m);

    // —— 日历 ——
    static UIElement CalendarW(Ctx c)
    {
        var now = DateTime.Now;
        var ws = c.M.Store.WeekStart;
        var first = new DateTime(now.Year, now.Month, 1);
        int offset = ((int)first.DayOfWeek - ws + 7) % 7;
        var start = first.AddDays(-offset);
        var heads = Strings.En ? new[] { "S", "M", "T", "W", "T", "F", "S" } : new[] { "日", "一", "二", "三", "四", "五", "六" };
        var grid = new UniformGrid7(7);
        for (int i = 0; i < 7; i++) grid.Add(Center(UI.T(heads[(i + ws) % 7], 10.5, c.P.Text3)));
        var evDays = new HashSet<DateTime>(c.M.Events.Select(e => U.ToLocal(e.Start).Date));
        int rows = c.It.Size == "T" ? 6 : ((offset + DateTime.DaysInMonth(now.Year, now.Month) + 6) / 7);
        for (int i = 0; i < rows * 7; i++)
        {
            var d = start.AddDays(i);
            var isToday = d.Date == now.Date;
            var t = UI.T(d.Day.ToString(), 12, isToday ? Brushes.White : d.Month == now.Month ? c.P.Text : c.P.Text3, isToday ? FontWeights.SemiBold : FontWeights.Normal, UI.Num);
            t.HorizontalAlignment = HorizontalAlignment.Center;
            var cell = new Grid { Height = 22 };
            if (isToday) cell.Children.Add(new Ellipse { Fill = c.P.AccentB, Width = 22, Height = 22 });
            cell.Children.Add(t);
            if (evDays.Contains(d.Date) && !isToday) cell.Children.Add(new Ellipse { Fill = c.P.AccentB, Width = 4, Height = 4, VerticalAlignment = VerticalAlignment.Bottom, HorizontalAlignment = HorizontalAlignment.Center, Margin = new Thickness(0, 0, 0, -3) });
            grid.Add(cell);
        }
        var body = new StackPanel();
        body.Children.Add(grid.Panel);
        var ms = U.NowMs();
        var upcoming = c.M.Events.Where(e => e.End > ms).Take(c.It.Size == "T" ? 6 : 2).ToList();
        foreach (var e in upcoming)
        {
            var when = U.ToLocal(e.Start).Date == now.Date ? (e.AllDay ? L("今天") : Hm(e.Start)) : U.ToLocal(e.Start).ToString(Strings.En ? "MMM d" : "M月d日", Culture);
            var row = UI.H(8, new Border { Width = 3, Height = 14, CornerRadius = new CornerRadius(2), Background = c.P.AccentB }, UI.T(when, 12, c.P.Text2, null, UI.Num), UI.T(e.Title, 12.5, c.P.Text));
            row.Margin = new Thickness(0, 8, 0, 0);
            body.Children.Add(row);
        }
        if (upcoming.Count == 0 && c.M.Store.IcsList.Count == 0)
            body.Children.Add(new TextBlock { Text = L("在设置 → 日程里加日历订阅链接"), Foreground = c.P.Text3, FontSize = 11.5, Margin = new Thickness(0, 8, 0, 0), TextWrapping = TextWrapping.Wrap });
        var title = now.ToString(Strings.En ? "MMMM yyyy" : "yyyy年M月", Culture);
        return Stack(c, Head(c, G.Calendar, title), body);
    }

    static FrameworkElement Center(FrameworkElement e) { e.HorizontalAlignment = HorizontalAlignment.Center; return e; }

    /** 7 列的小网格 */
    class UniformGrid7
    {
        public readonly System.Windows.Controls.Primitives.UniformGrid Panel;
        public UniformGrid7(int cols) { Panel = new() { Columns = cols }; }
        public void Add(UIElement e) => Panel.Children.Add(e);
    }

    // —— 邮件 ——
    static UIElement MailW(Ctx c)
    {
        var m = c.M.Mail;
        var head = Head(c, G.Mail, c.Title(L("邮件")), m is { Ok: true } ? UI.T(L("%@ 封未读", m.Unread), 11.5, c.P.Text3) : null);
        if (ImapMail.From(c.M.Store) == null) return Stack(c, head, Empty(c, L("在设置 → 邮件里连上你的邮箱（Gmail、Outlook、QQ、163…）")));
        if (m == null) return Stack(c, head, Empty(c, L("加载中…")));
        if (!m.Ok) return Stack(c, head, Empty(c, m.Error ?? L("读取失败")));
        if (m.Items.Count == 0) return Stack(c, head, Empty(c, L("没有未读邮件")));
        var list = new StackPanel();
        foreach (var it in m.Items.Take(Fit(Body(c), 40)))
        {
            var row = UI.V(1,
                UI.Row(UI.T(it.Name, 13, c.P.Text, FontWeights.SemiBold), UI.T(it.Ts is double t ? Rel(t) : "", 11, c.P.Text3)),
                UI.T(it.Subject, 12.5, c.P.Text2));
            row.Margin = new Thickness(0, 0, 0, 8);
            row.Background = Brushes.Transparent;
            Clickable(row, c, () => OpenMail?.Invoke(it));
            list.Children.Add(row);
        }
        return Stack(c, head, list);
    }

    // —— 新闻 / 订阅 ——
    static UIElement NewsList(Ctx c, IEnumerable<NewsItem> items, bool showSource)
    {
        var list = new StackPanel();
        bool roomy = c.It.Size != "M";
        foreach (var n in items.Take(Fit(Body(c), roomy ? 44 : 24)))
        {
            UIElement row = roomy
                ? UI.V(1, UI.T(n.Title, 13, c.P.Text), UI.T((showSource && n.Source != "" ? n.Source + " · " : "") + Rel(n.Ts), 11, c.P.Text3))
                : UI.Row(UI.T(n.Title, 13, c.P.Text), UI.T(Rel(n.Ts), 11, c.P.Text3));
            var fe = (FrameworkElement)row;
            fe.Margin = new Thickness(0, 0, 0, roomy ? 8 : 4);
            if (fe is Panel pnl) pnl.Background = Brushes.Transparent;
            Clickable(fe, c, () => UI.Open(n.Link));
            list.Children.Add(row);
        }
        return list;
    }

    static UIElement NewsW(Ctx c)
    {
        var tag = c.Cfg.S("tag") ?? "";
        var items = c.M.NewsItems.Where(n => tag == "" || n.Tag == tag).ToList();
        return Stack(c, Head(c, G.News, c.Title(tag == "" ? L("新闻") : L(tag))), items.Count == 0 ? Empty(c, L("加载中…")) : NewsList(c, items, true));
    }

    static UIElement Rss(Ctx c)
    {
        var url = c.Cfg.S("url") ?? "";
        if (!url.StartsWith("http")) return Stack(c, Head(c, G.News, c.Title(L("订阅"))), Empty(c, L("点齿轮填一个 RSS / Atom 地址")));
        if (!c.M.Feeds.TryGetValue(url, out var f)) return Stack(c, Head(c, G.News, c.Title(L("订阅"))), Empty(c, L("加载中…")));
        return Stack(c, Head(c, G.News, c.Title(f.title == "" ? L("订阅") : f.title)), NewsList(c, f.items, false));
    }

    // —— 世界时钟 ——
    public static readonly (string id, string zh, string en)[] Zones =
    {
        ("Asia/Shanghai", "北京", "Beijing"), ("Asia/Hong_Kong", "香港", "Hong Kong"), ("Asia/Tokyo", "东京", "Tokyo"), ("Asia/Singapore", "新加坡", "Singapore"),
        ("Europe/London", "伦敦", "London"), ("Europe/Paris", "巴黎", "Paris"), ("America/New_York", "纽约", "New York"), ("America/Chicago", "芝加哥", "Chicago"),
        ("America/Los_Angeles", "洛杉矶", "Los Angeles"), ("Australia/Sydney", "悉尼", "Sydney"), ("Asia/Dubai", "迪拜", "Dubai"), ("Asia/Seoul", "首尔", "Seoul"),
    };

    static UIElement WorldClock(Ctx c)
    {
        var zs = c.Cfg.L("zones");
        if (zs.Count == 0) zs = Strings.En ? new() { "America/New_York", "Europe/London", "Asia/Shanghai" } : new() { "Asia/Shanghai", "America/New_York", "Europe/London" };
        var list = new StackPanel();
        var now = DateTimeOffset.UtcNow;
        foreach (var z in zs.Take(Fit(Body(c), 28)))
        {
            var t = TimeZoneInfo.ConvertTime(now, U.Zone(z));
            var name = Zones.FirstOrDefault(x => x.id == z) is var hit && hit.id != null ? (Strings.En ? hit.en : hit.zh) : z.Split('/').Last().Replace('_', ' ');
            var dayDiff = (t.Date - DateTime.Now.Date).Days;
            var right = UI.H(6, dayDiff != 0 ? UI.T(dayDiff > 0 ? L("明天") : L("昨天"), 11, c.P.Text3) : null, UI.T(t.ToString("HH:mm"), 17, c.P.Text, FontWeights.Medium, UI.Num));
            list.Children.Add(UI.Row(UI.T(name, 13, c.P.Text2), right, 28));
        }
        return Stack(c, Head(c, G.Globe, c.Title(L("世界时钟"))), list);
    }

    // —— 待办（Windows 版存在本机；浮层里能加、能勾） ——
    static UIElement Todo(Ctx c)
    {
        var items = c.M.Todos(c.It.Id);
        var open = items.Where(t => !t.Done).ToList();
        var list = new StackPanel();
        foreach (var t in open.Take(Fit(Body(c) - (c.Interactive ? 34 : 0), 26)))
        {
            var dot = new Ellipse { Width = 14, Height = 14, Stroke = c.P.Text3, StrokeThickness = 1.4, VerticalAlignment = VerticalAlignment.Center };
            var row = UI.H(8, dot, UI.T(t.Title, 13, c.P.Text), t.Due != "" ? UI.T(t.Due[5..], 11, c.P.Text3) : null);
            row.Height = 26;
            row.Background = Brushes.Transparent;
            if (c.Interactive)
            {
                dot.Cursor = Cursors.Hand;
                dot.MouseLeftButtonUp += (_, e) => { t.Done = true; c.M.SaveTodos(c.It.Id, items); e.Handled = true; };
            }
            list.Children.Add(row);
        }
        if (c.Interactive)
        {
            var box = new TextBox { FontSize = 13, Foreground = c.P.Text, Background = c.P.Fill, BorderThickness = new Thickness(0), Padding = new Thickness(8, 5, 8, 5), CaretBrush = c.P.Text, Margin = new Thickness(0, 6, 0, 0) };
            var hint = UI.T(L("加一条，回车保存"), 12.5, c.P.Text3);
            hint.IsHitTestVisible = false; hint.Margin = new Thickness(10, 11, 0, 0);
            box.TextChanged += (_, _) => hint.Visibility = box.Text == "" ? Visibility.Visible : Visibility.Collapsed;
            box.KeyDown += (_, e) =>
            {
                if (e.Key != Key.Enter || box.Text.Trim() == "") return;
                // 已完成的只留最近 50 条，免得越存越多
                var keep = items.Where(x => !x.Done).Concat(items.Where(x => x.Done).TakeLast(50)).ToList();
                keep.Add(new TodoItem { Title = box.Text.Trim() });
                c.M.SaveTodos(c.It.Id, keep);
            };
            var g = new Grid(); g.Children.Add(box); g.Children.Add(hint);
            list.Children.Add(g);
        }
        else if (open.Count == 0) return Stack(c, Head(c, G.Check, c.Title(L("待办"))), Empty(c, L("没有待办。在浮层里加一条")));
        return Stack(c, Head(c, G.Check, c.Title(L("待办")), UI.T(open.Count.ToString(), 12, c.P.Text3)), list);
    }

    // —— 倒数日 ——
    static UIElement CountdownW(Ctx c)
    {
        var items = (c.Cfg.O["items"] as System.Text.Json.Nodes.JsonArray ?? new()).Select(x => (title: U.Str(x?["title"]) ?? "", date: U.Str(x?["date"]) ?? ""))
            .Select(x => (x.title, days: Countdown.Days(x.date))).Where(x => x.days != null).OrderBy(x => x.days < 0 ? 99999 : x.days).ToList();
        if (items.Count == 0) return Stack(c, Head(c, G.Calendar, c.Title(L("倒数日"))), Empty(c, L("点齿轮加一个日子")));
        if (c.It.Size == "S" || items.Count == 1)
        {
            var x = items[0];
            return Stack(c, Head(c, G.Calendar, c.Title(x.title)), UI.V(0,
                UI.H(4, UI.T(Math.Abs(x.days!.Value).ToString(), 40, c.P.Text, FontWeights.Light, UI.Num), UI.T(L("天"), 14, c.P.Text2)),
                UI.T(x.days == 0 ? L("就是今天") : x.days > 0 ? L("还有") : L("已经过去"), 12, c.P.Text3)));
        }
        var list = new StackPanel();
        foreach (var x in items.Take(Fit(Body(c), 28)))
            list.Children.Add(UI.Row(UI.T(x.title, 13, c.P.Text), UI.T(x.days == 0 ? L("今天") : x.days > 0 ? L("%@ 天", x.days) : L("%@ 天前", -x.days!), 13, c.P.Text2, null, UI.Num), 28));
        return Stack(c, Head(c, G.Calendar, c.Title(L("倒数日"))), list);
    }

    // —— 加密货币 ——
    static UIElement CryptoW(Ctx c)
    {
        var (coins, vs) = c.M.CryptoCfg(c.It.Id);
        var list = new StackPanel();
        foreach (var id in coins.Take(Fit(Body(c), 28)))
        {
            c.M.Coins.TryGetValue(id + "," + vs, out var q);
            var ch = q?.Change;
            var right = UI.H(10, UI.T(q == null ? "—" : Price(q.Price), 13.5, c.P.Text, FontWeights.Medium, UI.Num),
                UI.T(ch is double x ? (x >= 0 ? "+" : "") + x.ToString("0.0", CultureInfo.InvariantCulture) + "%" : "", 12, ch > 0 ? c.P.Up : c.P.Down, null, UI.Num));
            list.Children.Add(UI.Row(UI.T(Crypto.Symbol.GetValueOrDefault(id, id.ToUpperInvariant()), 13.5, c.P.Text), right, 28));
        }
        return Stack(c, Head(c, G.Money, c.Title(L("加密货币")), UI.T(vs.ToUpperInvariant(), 11, c.P.Text3)), list);
    }

    // —— GitHub ——
    static UIElement GitHubW(Ctx c)
    {
        var list = new StackPanel();
        foreach (var r in c.M.RepoList(c.It.Id).Take(Fit(Body(c), 40)))
        {
            c.M.Repos.TryGetValue(r, out var info);
            var row = UI.V(1, UI.T(r, 13, c.P.Text, FontWeights.Medium),
                UI.T(info == null ? L("加载中…") : $"★ {info.Stars}   ⑂ {info.Forks}   ⓘ {info.Issues}" + (info.Downloads is int d ? "   ↓ " + d : ""), 12, c.P.Text2, null, UI.Num));
            row.Margin = new Thickness(0, 0, 0, 8);
            row.Background = Brushes.Transparent;
            Clickable(row, c, () => UI.Open("https://github.com/" + r));
            list.Children.Add(row);
        }
        return Stack(c, Head(c, G.Star, c.Title("GitHub")), list);
    }

    // —— 照片 ——
    static UIElement PhotoW(Ctx c)
    {
        var path = c.M.Photo(c.It.Id);
        if (path == null) return Empty(c, L("照片文件夹里没有照片。点齿轮换一个文件夹"));
        try
        {
            var bmp = new BitmapImage();
            bmp.BeginInit();
            bmp.UriSource = new Uri(path);
            bmp.CacheOption = BitmapCacheOption.OnLoad;
            bmp.DecodePixelWidth = (int)Math.Min(1600, c.W * 2);
            bmp.EndInit();
            bmp.Freeze();
            var img = new Border { Background = new ImageBrush(bmp) { Stretch = Stretch.UniformToFill }, CornerRadius = new CornerRadius(12), Margin = new Thickness(-8) };
            Clickable(img, c, () => c.M.Photo(c.It.Id, true));
            return img;
        }
        catch { return Empty(c, System.IO.Path.GetFileName(path)); }
    }

    // —— 番茄钟 ——
    static UIElement Pomodoro(Ctx c)
    {
        var m = c.M;
        var left = (int)m.PomoLeft;
        var text = $"{left / 60:00}:{left % 60:00}";
        var big = UI.T(text, c.It.Size == "S" ? 34 : 44, m.PomoRunning ? c.P.AccentB : c.P.Text, FontWeights.Light, UI.Num);
        var pct = 1 - m.PomoLeft / Math.Max(1, m.PomoMinutes * 60);
        var body = UI.V(6, big, UI.Bar(pct, Math.Max(40, c.W - 40), c.P.AccentB, c.P.Fill2, 4),
            c.Interactive ? UI.H(6, UI.Pill(m.PomoRunning ? L("暂停") : L("开始"), c.P, m.PomoToggle, true), UI.Pill(L("重来"), c.P, () => m.PomoReset())) : UI.T(m.PomoRunning ? L("专注中") : L("在浮层里开始"), 11.5, c.P.Text3));
        return Stack(c, Head(c, G.Timer, c.Title(L("番茄钟"))), body);
    }

    // —— 系统状态 ——
    static UIElement SysW(Ctx c)
    {
        var s = c.M.Sys;
        double barW = Math.Max(40, c.W - 120);
        UIElement Bar(string name, int? v, string note = "") => UI.Row(UI.H(8, UI.T(name, 11.5, c.P.Text2), UI.Bar((v ?? 0) / 100.0, barW - (note == "" ? 0 : 60), (v ?? 0) >= 85 ? c.P.Orange : c.P.AccentB, c.P.Fill2)),
            UI.H(6, UI.T(v == null ? "—" : v + "%", 12, c.P.Text, FontWeights.Medium, UI.Num), note == "" ? null : UI.T(note, 10.5, c.P.Text3)), 22);
        var p = new StackPanel();
        p.Children.Add(Bar("CPU", s.Cpu));
        p.Children.Add(Bar(L("内存"), s.Mem));
        if (c.It.Size != "S")
        {
            if (s.DiskFree is double f && s.DiskTotal is double t && t > 0) p.Children.Add(Bar(L("磁盘"), (int)Math.Round((t - f) / t * 100), L("剩 %@", SysSampler.Gb(f))));
            var net = UI.H(14, UI.T("↓ " + SysSampler.Speed(s.Down), 11.5, c.P.Text2, null, UI.Num), UI.T("↑ " + SysSampler.Speed(s.Up), 11.5, c.P.Text2, null, UI.Num),
                s.Battery is int b ? UI.T((s.Charging ? "⚡" : "🔋") + b + "%", 11.5, c.P.Text2, null, UI.Num) : null);
            net.Margin = new Thickness(0, 6, 0, 0);
            p.Children.Add(net);
        }
        return Stack(c, Head(c, G.Cpu, c.Title(L("系统状态"))), p);
    }

    // —— 便签（浮层里直接改，停手一秒自动保存） ——
    static UIElement NoteW(Ctx c)
    {
        var text = c.Cfg.S("text") ?? "";
        if (!c.Interactive)
            return Stack(c, Head(c, G.Note, c.Title(L("便签"))), new TextBlock { Text = text == "" ? L("在浮层里点这里写点什么") : text, Foreground = text == "" ? c.P.Text3 : c.P.Text, FontSize = 13.5, FontFamily = UI.Font, TextWrapping = TextWrapping.Wrap });
        var box = new TextBox
        {
            Text = text, AcceptsReturn = true, TextWrapping = TextWrapping.Wrap, FontSize = 13.5, FontFamily = UI.Font, Foreground = c.P.Text, CaretBrush = c.P.Text,
            Background = c.P.Fill, BorderThickness = new Thickness(0), Padding = new Thickness(6), VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
        };
        var timer = new System.Windows.Threading.DispatcherTimer { Interval = TimeSpan.FromSeconds(0.8) };
        timer.Tick += (_, _) => { timer.Stop(); var cfg = c.M.Store.Config(c.It.Id); cfg["text"] = box.Text; c.M.Store.SetConfig(c.It.Id, cfg); };
        box.TextChanged += (_, _) => { timer.Stop(); timer.Start(); };
        return Stack(c, Head(c, G.Note, c.Title(L("便签"))), box);
    }

    // —— 汇率 ——
    static UIElement FxW(Ctx c)
    {
        var b = c.M.FxBase(c.It.Id);
        var targets = c.Cfg.L("targets");
        if (targets.Count == 0) targets = b == "CNY" ? new() { "USD", "EUR", "JPY", "HKD" } : new() { "CNY", "EUR", "JPY", "GBP" };
        var amount = c.Cfg.N("amount") ?? (b == "CNY" ? 100 : 1);
        var head = Head(c, G.Money, c.Title(L("汇率")), UI.T($"{U.JsNum(amount)} {b}", 11, c.P.Text3));
        if (!c.M.Rates.TryGetValue(b, out var r)) return Stack(c, head, Empty(c, L("加载中…")));
        var list = new StackPanel();
        foreach (var t in targets.Take(Fit(Body(c), 28)))
        {
            var v = r.rates.TryGetValue(t, out var x) ? x * amount : (double?)null;
            var name = UI.H(6, UI.T(t, 13, c.P.Text, FontWeights.Medium), Strings.En ? null : UI.T(FX.Names.GetValueOrDefault(t, ""), 11, c.P.Text3));
            list.Children.Add(UI.Row(name, UI.T(v is double y ? y.ToString(y >= 100 ? "N2" : "N4", CultureInfo.InvariantCulture) : "—", 13, c.P.Text, null, UI.Num), 28));
        }
        list.ToolTip = L("open.er-api.com 公开汇率，每天更新，仅供参考");
        return Stack(c, head, list);
    }

    // —— 农历 ——
    static UIElement LunarW(Ctx c)
    {
        var now = U.NowMs();
        var next = Lunar.Next(now);
        return Stack(c, Head(c, G.Moon, c.Title(L("农历"))), UI.V(4,
            UI.T(Lunar.Text(now), c.It.Size == "S" ? 18 : 22, c.P.Text, FontWeights.SemiBold),
            next is var (name, days) ? UI.T(days == 0 ? L("今天是%@", L(name)) : L("%@ · 还有 %@ 天", L(name), days), 12, days == 0 ? c.P.AccentB : c.P.Text2) : null));
    }

    // —— 正在播放 ——
    static UIElement NowPlayingW(Ctx c)
    {
        var np = c.M.Playing;
        var head = Head(c, G.Music, c.Title(L("正在播放")), np == null ? null : UI.T(np.App, 11, c.P.Text3));
        if (np == null) return Stack(c, head, Empty(c, L("Spotify、网易云、QQ 音乐或浏览器放歌时显示在这里")));
        Border art;
        if (np.Art != null)
        {
            try
            {
                var bmp = new BitmapImage(); bmp.BeginInit(); bmp.StreamSource = new MemoryStream(np.Art); bmp.CacheOption = BitmapCacheOption.OnLoad; bmp.DecodePixelWidth = 120; bmp.EndInit(); bmp.Freeze();
                art = new Border { Width = 46, Height = 46, CornerRadius = new CornerRadius(8), Background = new ImageBrush(bmp) { Stretch = Stretch.UniformToFill } };
            }
            catch { art = ArtPlaceholder(c); }
        }
        else art = ArtPlaceholder(c);
        var info = UI.V(2, UI.T(np.Title, 13.5, c.P.Text, FontWeights.SemiBold), UI.T(np.Artist, 12, c.P.Text2));
        info.VerticalAlignment = VerticalAlignment.Center;
        var top = new DockPanel();
        DockPanel.SetDock(art, Dock.Left); art.Margin = new Thickness(0, 0, 12, 0); top.Children.Add(art);
        if (c.Interactive)
        {
            var ctl = UI.H(2, UI.IconButton(G.Prev, c.P, () => _ = c.M.PlayerCommand("prev"), 14), UI.IconButton(np.Playing ? G.Pause : G.Play, c.P, () => _ = c.M.PlayerCommand("toggle"), 16), UI.IconButton(G.Next, c.P, () => _ = c.M.PlayerCommand("next"), 14));
            DockPanel.SetDock(ctl, Dock.Right); ctl.VerticalAlignment = VerticalAlignment.Center; top.Children.Add(ctl);
        }
        top.Children.Add(info);
        var body = new StackPanel();
        body.Children.Add(top);
        if (np.Duration > 0)
        {
            var p = np.Pos(DateTime.UtcNow);
            static string Mmss(double s) => $"{(int)s / 60}:{(int)s % 60:00}";
            var bar = UI.Row(UI.H(8, UI.T(Mmss(p), 10.5, c.P.Text3, null, UI.Num), UI.Bar(p / np.Duration, Math.Max(40, c.W - 110), c.P.Text2, c.P.Fill2, 4)), UI.T(Mmss(np.Duration), 10.5, c.P.Text3, null, UI.Num));
            bar.Margin = new Thickness(0, 10, 0, 0);
            body.Children.Add(bar);
        }
        return Stack(c, head, body);
    }

    static Border ArtPlaceholder(Ctx c) => new()
    {
        Width = 46, Height = 46, CornerRadius = new CornerRadius(8),
        Background = new LinearGradientBrush(Color.FromArgb(200, c.P.Accent.R, c.P.Accent.G, c.P.Accent.B), Color.FromArgb(150, 255, 149, 0), 45),
        Child = new TextBlock { Text = G.Music, FontFamily = UI.Icons, FontSize = 18, Foreground = Brushes.White, HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center },
    };
}
