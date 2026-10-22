// 设置：通用、桌面、Dock、邮件、日程、行情与新闻、AI、关于。改了马上生效、马上存（密码要点「保存」）。
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json.Nodes;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using DeskHub.Core;
using static DeskHub.Core.I18n;

namespace DeskHub;

public class SettingsWindow : Window
{
    readonly Model m;
    readonly StackPanel nav = new() { Margin = new Thickness(12, 16, 12, 16) };
    readonly ScrollViewer page = new() { VerticalScrollBarVisibility = ScrollBarVisibility.Auto, Padding = new Thickness(28, 22, 28, 28) };
    string current;
    Palette P => m.Pal;

    static readonly (string id, string zh)[] Pages =
    {
        ("general", "通用"), ("desktop", "桌面"), ("dock", "Dock"), ("mail", "邮件"), ("calendar", "日程"), ("market", "行情与新闻"), ("ai", "AI"), ("about", "关于"),
    };

    public SettingsWindow(Model m, string start = "general")
    {
        this.m = m;
        current = start;
        Width = 900; Height = 640; MinWidth = 720; MinHeight = 480;
        WindowStartupLocation = WindowStartupLocation.CenterScreen;
        FontFamily = UI.Font;
        try { Icon = System.Windows.Media.Imaging.BitmapFrame.Create(new Uri("pack://application:,,,/icon.ico")); } catch { }
        m.Changed += OnChanged;
        Closed += (_, _) => m.Changed -= OnChanged;
        Closing += (_, _) => System.Windows.Input.Keyboard.ClearFocus();
        Draw();
    }

    void OnChanged(HashSet<string> keys) { if (keys.Contains("theme") || keys.Contains("lang")) Draw(); }

    void Draw()
    {
        System.Windows.Input.Keyboard.ClearFocus();   // 让正在改的输入框先存一下
        Title = L("设置") + " · DeskHub";
        Background = P.Window;
        nav.Children.Clear();
        foreach (var (id, zh) in Pages)
        {
            var on = id == current;
            var b = new Border { CornerRadius = new CornerRadius(8), Padding = new Thickness(12, 7, 12, 8), Margin = new Thickness(0, 0, 0, 2), Background = on ? P.Fill2 : Brushes.Transparent, Cursor = System.Windows.Input.Cursors.Hand,
                Child = UI.T(L(zh), 13.5, on ? P.Text : P.Text2, on ? FontWeights.SemiBold : FontWeights.Normal) };
            var pid = id;
            b.MouseLeftButtonUp += (_, _) => { current = pid; Draw(); };
            nav.Children.Add(b);
        }
        var body = new StackPanel { MaxWidth = 620, HorizontalAlignment = HorizontalAlignment.Left };
        body.Children.Add(UI.T(L(Pages.First(p => p.id == current).zh), 24, P.Text, FontWeights.SemiBold));
        switch (current)
        {
            case "general": General(body); break;
            case "desktop": Desktop(body); break;
            case "dock": Dock(body); break;
            case "mail": Mail(body); break;
            case "calendar": Calendar(body); break;
            case "market": MarketNews(body); break;
            case "ai": Ai(body); break;
            default: About(body); break;
        }
        page.Content = body;
        var root = new DockPanel();
        var left = new Border { Width = 190, Background = P.Fill, Child = nav };
        DockPanel.SetDock(left, System.Windows.Controls.Dock.Left);
        root.Children.Add(left);
        root.Children.Add(page);
        Content = root;
    }

    // —— 表单小部件 ——
    void Section(StackPanel to, string title, params UIElement?[] rows)
    {
        var box = new StackPanel();
        foreach (var r in rows) if (r != null) { if (r is FrameworkElement f) f.Margin = new Thickness(0, 6, 0, 6); box.Children.Add(r); }
        var head = UI.T(title, 12, P.Text3, FontWeights.SemiBold);
        head.Margin = new Thickness(4, 22, 0, 6);
        to.Children.Add(head);
        to.Children.Add(new Border { Background = P.Card, BorderBrush = P.CardBorder, BorderThickness = new Thickness(1), CornerRadius = new CornerRadius(12), Padding = new Thickness(16, 8, 16, 8), Child = box });
    }

    UIElement Line(string label, UIElement right, string? note = null)
    {
        var l = UI.V(2, UI.T(label, 13.5, P.Text), note == null ? null : UI.Wrap(note, 11.5, P.Text3));
        l.HorizontalAlignment = HorizontalAlignment.Left;
        l.Margin = new Thickness(0, 0, 16, 0);
        var row = UI.Row(l, right);
        row.MinHeight = 30;
        return row;
    }

    CheckBox Toggle(bool on, Action<bool> set)
    {
        var c = new CheckBox { IsChecked = on, VerticalAlignment = VerticalAlignment.Center };
        c.Checked += (_, _) => set(true);
        c.Unchecked += (_, _) => set(false);
        return c;
    }

    WrapPanel Chips(string[] values, string[] labels, string cur, Action<string> set)
    {
        var w = new WrapPanel { HorizontalAlignment = HorizontalAlignment.Right };
        for (int i = 0; i < values.Length; i++)
        {
            var v = values[i];
            var on = v == cur;
            var b = new Border { CornerRadius = new CornerRadius(9), Padding = new Thickness(10, 3, 10, 4), Margin = new Thickness(4, 2, 0, 2), Background = on ? P.AccentB : P.Fill2, Cursor = System.Windows.Input.Cursors.Hand,
                Child = new TextBlock { Text = labels[i], FontSize = 12.5, Foreground = on ? Brushes.White : P.Text } };
            b.MouseLeftButtonUp += (_, _) => { set(v); Draw(); };
            w.Children.Add(b);
        }
        return w;
    }

    TextBox Input(string text, double width = 260)
    {
        return new TextBox { Text = text, Width = width, FontSize = 13, Padding = new Thickness(8, 5, 8, 5), Foreground = P.Text, Background = P.Fill, BorderBrush = P.CardBorder, CaretBrush = P.Text };
    }

    /** 输入框里的灰色提示字（一打字就消失） */
    Grid WithHint(TextBox box, string hint)
    {
        var t = UI.T(hint, 12.5, P.Text3);
        t.IsHitTestVisible = false; t.Margin = new Thickness(10, 0, 0, 0); t.VerticalAlignment = VerticalAlignment.Center;
        box.TextChanged += (_, _) => t.Visibility = box.Text == "" ? Visibility.Visible : Visibility.Collapsed;
        var g = new Grid(); g.Children.Add(box); g.Children.Add(t);
        return g;
    }

    PasswordBox Secret(double width = 260) => new() { Width = width, FontSize = 13, Padding = new Thickness(8, 5, 8, 5), Foreground = P.Text, Background = P.Fill, BorderBrush = P.CardBorder, CaretBrush = P.Text };

    TextBlock Hint(string text) { var t = UI.Wrap(text, 12, P.Text3); return t; }

    TextBlock Link(string text, string url)
    {
        var t = UI.T(text, 12.5, P.AccentB);
        t.Cursor = System.Windows.Input.Cursors.Hand;
        t.MouseLeftButtonUp += (_, _) => UI.Open(url);
        return t;
    }

    void SetMail(string k, JsonNode? v) { var o = (JsonObject)m.Store.Mail.DeepClone(); if (v == null) o.Remove(k); else o[k] = v; m.Store.Set("mail", o); }
    void SetCal(string k, JsonNode? v) { var o = (JsonObject)U.Obj(m.Store.Data["calendar"]).DeepClone(); o[k] = v; m.Store.Set("calendar", o); }

    // —— 各页 ——
    void General(StackPanel b)
    {
        var s = m.Store;
        var name = Input(s.ButlerName, 160);
        name.LostFocus += (_, _) => s.Set("butlerName", name.Text.Trim());
        Section(b, L("语言和外观"),
            Line(L("语言"), Chips(new[] { "zh", "en" }, new[] { "中文", "English" }, s.Lang, v => s.Set("lang", v))),
            Line(L("外观"), Chips(new[] { "auto", "light", "dark" }, new[] { L("跟随系统"), L("浅色"), L("深色") }, s.Theme, v => s.Set("theme", v))),
            Line(L("强调色"), Chips(Palette.Accents.Select(a => a.id).ToArray(), Palette.Accents.Select(a => L(a.zh)).ToArray(), s.Accent, v => s.Set("accent", v))),
            Line(L("涨跌颜色"), Chips(new[] { "mono", "rup", "gup" }, new[] { L("中性"), L("红涨绿跌"), L("绿涨红跌") }, s.Colors, v => s.Set("colors", v))));
        Section(b, L("管家"),
            Line(L("管家的名字"), name, L("问问题、写提醒时都用这个名字")));
        Section(b, L("启动和更新"),
            Line(L("开机自动启动"), Toggle(AutoStart.Enabled, v => AutoStart.Enabled = v)),
            Line(L("版本 %@", App.Version), UI.Pill(m.NewVersion != null ? L("下载新版本 %@", m.NewVersion.Version) : L("检查更新"), P, () =>
            {
                if (m.NewVersion != null) UI.Open(m.NewVersion.Page); else { m.Kick("update"); UI.Open(Update.ReleasesPage); }
            }, m.NewVersion != null), L("每天自动看一次 GitHub 上有没有新版本，只提示，不会自动下载安装")));
    }

    void Desktop(StackPanel b)
    {
        var s = m.Store;
        var cityQ = Input("", 180);
        var results = new StackPanel();
        async void Search()
        {
            results.Children.Clear();
            try
            {
                foreach (var x in WeatherApi.ParseSearch(await Net.Json(WeatherApi.SearchUrl(cityQ.Text.Trim(), Strings.En ? "en" : "zh"))))
                {
                    var hit = x;
                    var pill = UI.Pill($"{x.name}  {x.region}", P, () => { s.Set("city", new JsonObject { ["name"] = hit.name, ["lat"] = hit.lat, ["lon"] = hit.lon }); Draw(); });
                    pill.HorizontalAlignment = HorizontalAlignment.Left; pill.Margin = new Thickness(0, 4, 0, 0);
                    results.Children.Add(pill);
                }
            }
            catch { results.Children.Add(Hint(L("搜索失败，检查一下网络"))); }
        }
        cityQ.KeyDown += (_, e) => { if (e.Key == System.Windows.Input.Key.Enter) Search(); };
        Section(b, L("桌面"),
            Line(L("清空桌面（隐藏桌面图标）"), Toggle(s.WinFlag("hideIcons", false), v => { s.SetWin("hideIcons", v); Native.SetDesktopIconsVisible(!v); }), L("只是藏起来，文件都还在桌面文件夹里；关掉这个开关或退出程序就回来")),
            Line(L("每块屏幕都显示组件"), Toggle(s.WinFlag("allScreens", true), v => { s.SetWin("allScreens", v); App.Instance.RebuildDesks(); }), L("每块屏幕的组件各摆各的")),
            Line(L("快捷键"), UI.T("Ctrl + Alt + Space", 13, P.Text2), L("随时呼出浮层：组件可以点、可以编辑")));
        Section(b, L("天气"),
            Line(L("城市"), UI.T(s.City.name, 13, P.Text2)),
            UI.V(4, UI.H(6, cityQ, UI.Pill(L("搜索"), P, Search)), results));
    }

    void Dock(StackPanel b)
    {
        var s = m.Store;
        Section(b, "Dock",
            Line(L("显示底部 Dock"), Toggle(s.WinFlag("dock", true), v => { s.SetWin("dock", v); App.Instance.ApplyDock(); })),
            Line(L("自动收起"), Toggle(s.WinFlag("dockAutoHide", false), v => s.SetWin("dockAutoHide", v)), L("鼠标离开一会儿就收成底部一条小横线，碰一下就展开")),
            Line(L("图标大小"), Chips(new[] { "S", "M", "L" }, new[] { L("小"), L("中"), L("大") }, U.Str(s.Win["dockSize"]) ?? "M", v => s.SetWin("dockSize", v))),
            Line(L("恢复默认的应用"), UI.Pill(L("恢复"), P, () => { var w = (JsonObject)s.Win.DeepClone(); w.Remove("dockApps"); s.Set("win", w); App.Instance.ApplyDock(true); })));
        b.Children.Add(Hint(L("把任何程序、快捷方式、文件、文件夹拖到 Dock 上就能放进去；在图标上点右键可以挪位置、移除。")));
        ((FrameworkElement)b.Children[^1]).Margin = new Thickness(4, 10, 0, 0);
    }

    void Mail(StackPanel b)
    {
        var mail = m.Store.Mail;
        var source = U.Str(mail["source"]) == "imap" ? "imap" : "off";
        Section(b, L("从哪里读邮件"),
            Line(L("来源"), Chips(new[] { "off", "imap" }, new[] { L("不读"), L("IMAP 邮箱") }, source, v => { SetMail("source", v); m.Kick("mail"); })));
        if (source != "imap")
        {
            b.Children.Add(Hint(L("邮件只读不写：不会标成已读、不会删、不会发。支持 Gmail、Outlook、iCloud、QQ、163 等所有 IMAP 邮箱。")));
            return;
        }
        var email = U.Str(mail["email"]) ?? "";
        var prov = MailProviders.By(U.Str(mail["provider"]) ?? (email == "" ? "gmail" : MailProviders.Guess(email)));
        var emailBox = Input(email);
        emailBox.LostFocus += (_, _) =>
        {
            var e = emailBox.Text.Trim();
            if (e == email) return;
            SetMail("email", e);
            if (U.Str(m.Store.Mail["provider"]) == null && e.Contains('@')) SetMail("provider", MailProviders.Guess(e));
            Draw();
        };
        var pass = Secret();
        var status = Hint(email != "" && Secrets.Get(ImapMail.SecretKey(email)) != null ? L("已保存密码（加密存在这台电脑上）") : "");
        var save = UI.Pill(L("保存并测试"), P, async () =>
        {
            var e = emailBox.Text.Trim();
            if (e == "") { status.Text = L("先填邮箱地址"); return; }
            SetMail("email", e);
            if (pass.Password != "") Secrets.Set(ImapMail.SecretKey(e), pass.Password);
            status.Text = L("正在连接…");
            var acct = ImapMail.From(m.Store);
            var err = acct == null ? L("设置不完整") : await ImapMail.Test(acct);
            status.Text = err == null ? L("✓ 连上了") : "✗ " + err;
            m.Kick("mail");
        }, true);
        var host = Input(U.Str(mail["host"]) ?? "", 200);
        host.LostFocus += (_, _) => SetMail("host", host.Text.Trim() == "" ? null : host.Text.Trim());
        var port = Input(U.Num(mail["port"]) is double pt ? U.JsNum(pt) : "993", 80);
        port.LostFocus += (_, _) => SetMail("port", int.TryParse(port.Text, out var n) ? n : null);
        var contacts = Input(string.Join(", ", m.Store.MailContacts));
        contacts.LostFocus += (_, _) =>
        {
            var r = (JsonObject)U.Obj(m.Store.Data["butlerRules"]).DeepClone();
            r["contacts"] = U.Arr(contacts.Text.Split(',', '，').Select(x => x.Trim()).Where(x => x != ""));
            m.Store.Set("butlerRules", r);
        };
        Section(b, L("邮箱"),
            Line(L("服务商"), Chips(MailProviders.All.Select(x => x.Id).ToArray(), MailProviders.All.Select(x => L(x.Name)).ToArray(), prov.Id, v => SetMail("provider", v))),
            Line(L("邮箱地址"), emailBox),
            Line(L("应用专用密码"), pass, L("大多数邮箱要用「应用专用密码 / 授权码」，不是网页登录密码。密码用 Windows 自带的加密存在这台电脑上，不会上传")),
            prov.Id == "custom" ? Line(L("IMAP 服务器"), UI.H(6, host, port)) : null,
            prov.Help != "" ? Line(L("怎么拿应用专用密码"), Link(L("打开 %@ 的设置页", L(prov.Name)), prov.Help)) : null,
            UI.H(10, save, status));
        Section(b, L("管家"),
            Line(L("重要的人"), contacts, L("这些人（邮箱或名字的一部分，用逗号分开）来信时，管家会排在最前面")));
    }

    void Calendar(StackPanel b)
    {
        var s = m.Store;
        var list = new StackPanel();
        var subs = s.IcsList;
        void Save(List<(string name, string url)> xs) =>
            SetCal("ics", new JsonArray(xs.Select(x => (JsonNode)new JsonObject { ["name"] = x.name, ["url"] = x.url }).ToArray()));
        for (int i = 0; i < subs.Count; i++)
        {
            int idx = i;
            var row = UI.Row(UI.V(1, UI.T(subs[i].name == "" ? L("订阅日历") : subs[i].name, 13.5, P.Text), UI.T(subs[i].url, 11, P.Text3)),
                UI.Pill(L("删除"), P, () => { var xs = s.IcsList; xs.RemoveAt(idx); Save(xs); Draw(); }));
            list.Children.Add(row);
        }
        var nameBox = Input("", 140);
        var urlBox = Input("", 300);
        var nameHost = WithHint(nameBox, L("名字（可不填）"));
        var urlHost = WithHint(urlBox, "https://…/basic.ics");
        var add = UI.Pill(L("添加"), P, () =>
        {
            var u = urlBox.Text.Trim();
            if (!u.StartsWith("http") && !u.StartsWith("webcal")) return;
            var xs = s.IcsList; xs.Add((nameBox.Text.Trim(), u)); Save(xs); m.Kick("calendar"); Draw();
        }, true);
        Section(b, L("日历订阅"),
            subs.Count == 0 ? Hint(L("还没有订阅。Windows 没有像 Mac 那样谁都能读的系统日历，所以用订阅链接：")) : list,
            UI.H(6, nameHost, urlHost, add),
            UI.V(3, Hint(L("· Google 日历：设置 → 选中日历 → 「iCal 格式的私密地址」")), Hint(L("· Outlook：设置 → 日历 → 共享日历 → 发布日历 → ICS 链接")), Hint(L("· 学校课表、节假日日历通常也有 .ics 链接"))),
            m.CalError != null ? Hint("✗ " + m.CalError) : null);
        Section(b, L("提醒和显示"),
            Line(L("日程开始前提醒"), Chips(new[] { "0", "5", "10", "15", "30" }, new[] { L("不提醒"), "5", "10", "15", "30" }.Select((x, i) => i == 0 ? x : L("%@ 分钟", x)).ToArray(), s.SoonMin.ToString(), v => SetCal("soonMin", int.Parse(v)))),
            Line(L("一周从哪天开始"), Chips(new[] { "1", "0" }, new[] { L("周一"), L("周日") }, s.WeekStart.ToString(), v => SetCal("weekStart", int.Parse(v)))));
    }

    void MarketNews(StackPanel b)
    {
        var s = m.Store;
        var watch = Input(string.Join(", ", s.Watch.Select(Market.DisplayCode)), 320);
        watch.LostFocus += (_, _) =>
        {
            var keys = watch.Text.Split(',', '，').Select(x => Market.ToSinaKey(x.Trim())).Where(x => x != null).Select(x => x!).Distinct();
            s.Set("watch", U.Arr(keys));
        };
        var pct = Input(U.JsNum(s.AlertPct), 60);
        pct.LostFocus += (_, _) => { if (double.TryParse(pct.Text, out var v)) s.Set("alertPct", v); };
        Section(b, L("行情"),
            Line(L("自选"), watch, L("A 股填 6 位数字，港股填 5 位数字，美股填字母代码，用逗号分开")),
            Line(L("涨跌提醒线（%）"), pct, L("涨跌幅超过这个数时发一条通知，每只每天一次；填 0 不提醒")),
            Hint(L("数据来自新浪公开接口，有延迟，只做展示和提醒，不构成任何投资建议。")));
        var on = s.NewsSources;
        var rows = News.Sources.Select(src => Line(L(src.Name), Toggle(on.Contains(src.Id), v =>
        {
            var cur = s.NewsSources;
            s.Set("newsSources", U.Arr(v ? cur.Append(src.Id).Distinct() : cur.Where(x => x != src.Id)));
        }))).ToArray();
        Section(b, L("新闻来源"), rows);
    }

    void Ai(StackPanel b)
    {
        var key = Secret(320);
        var status = Hint(DeepSeek.HasKey ? L("已保存（加密存在这台电脑上）") : L("还没填"));
        Section(b, "DeepSeek",
            Line(L("API Key"), key, L("在浮层顶部的输入框里问问题、让管家概括邮件时用。Key 用 Windows 自带的加密存在这台电脑上")),
            UI.H(10, UI.Pill(L("保存"), P, () => { Secrets.Set(DeepSeek.SecretKey, key.Password.Trim()); key.Password = ""; status.Text = DeepSeek.HasKey ? L("已保存（加密存在这台电脑上）") : L("还没填"); }, true),
                UI.Pill(L("清除"), P, () => { Secrets.Set(DeepSeek.SecretKey, null); status.Text = L("还没填"); }), status),
            Link(L("去 DeepSeek 开放平台拿 Key"), DeepSeek.KeyPage),
            Hint(L("问问题时会把现在的时间、天气、接下来的日程、未读邮件的标题和待办一起发给 DeepSeek，好让它答得准。不想发就别用这个功能。")));
    }

    void About(StackPanel b)
    {
        Section(b, "DeskHub",
            Line(L("版本"), UI.T(App.Version, 13, P.Text2)),
            Line(L("开源"), Link("github.com/" + Update.Repo, "https://github.com/" + Update.Repo)),
            Line(L("设置文件"), UI.Pill(L("打开文件夹"), P, () => UI.Open(Path.GetDirectoryName(Store.DefaultPath)!))),
            Hint(L("没有账号、不收集任何数据。天气、行情、新闻都是直接向公开接口请求；邮件密码和 API Key 用 Windows 自带的加密只存在这台电脑上。")));
    }
}
