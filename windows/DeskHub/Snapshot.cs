// 截图模式：Glancedesk.exe --snapshot <文件夹> [--lang en] [--theme dark]
// 用示例数据把桌面组件、浮层编辑态、Dock、设置各页、引导各页渲染成 PNG（不开窗口、不联网、不碰你的设置文件）。
// CI 在 Windows 机器上跑它，开发时不用开 Windows 电脑也能看界面。
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json.Nodes;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using DeskHub.Core;

namespace DeskHub;

static class Snapshot
{
    public static void Run(string dir, string lang, string theme)
    {
        Directory.CreateDirectory(dir);
        var tmp = Path.Combine(Path.GetTempPath(), "glancedesk-snap-" + Guid.NewGuid().ToString("N"), "desk.json");
        var store = new Store(tmp);
        store.Set(new JsonObject { ["lang"] = lang, ["theme"] = theme, ["onboarded"] = true, ["colors"] = "rup" });
        var m = new Model(store);
        Sample(m);

        // 1) 桌面：左右两列 + 中间也摆满，看所有组件
        var full = new JsonObject
        {
            ["version"] = DeskGrid.Version,
            ["items"] = new JsonArray(
                It("clock", 0, 0, "M"), It("butler", 0, 1, "M"), It("market", 0, 2, "L"),
                It("weather", 2, 0, "M"), It("calendar", 2, 1, "L"), It("mail", 2, 3, "M"),
                It("news", 4, 0, "L"), It("todo", 4, 2, "L"),
                It("worldclock", 6, 0, "M"), It("sysstat", 6, 1, "M"), It("fx", 6, 2, "M"), It("nowplaying", 6, 3, "M")),
        };
        store.Set("layout", full);
        Save(Desk(m, false, false), dir, "1-desk");
        var more = new JsonObject
        {
            ["version"] = DeskGrid.Version,
            ["items"] = new JsonArray(
                It("countdown", 0, 0, "M"), It("crypto", 0, 1, "M"), It("github", 0, 2, "M"), It("lunar", 0, 3, "S"), It("pomodoro", 1, 3, "S"),
                It("note", 2, 0, "M"), It("rss", 2, 1, "L"), It("clock", 4, 0, "S"), It("weather", 5, 0, "S"), It("market", 4, 1, "L"),
                It("calendar", 6, 0, "T"), It("butler", 6, 3, "M"), It("photo", 2, 3, "W")),
        };
        store.Set("layout", more);
        store.SetConfig("countdown", new JsonObject { ["items"] = new JsonArray(new JsonObject { ["title"] = I18n.L("期末考试"), ["date"] = DateTime.Today.AddDays(45).ToString("yyyy-MM-dd") }, new JsonObject { ["title"] = "Christmas", ["date"] = new DateTime(DateTime.Today.Year, 12, 25).ToString("yyyy-MM-dd") }) });
        store.SetConfig("note", new JsonObject { ["text"] = lang == "en" ? "Buy milk\nCall mom on Sunday" : "买牛奶\n周日给妈妈打电话" });
        store.SetConfig("rss", new JsonObject { ["url"] = "https://example.com/feed" });
        Save(Desk(m, false, false), dir, "2-desk-more");

        // 2) 浮层编辑态
        store.Set("layout", full);
        Save(Desk(m, true, true), dir, "3-overlay-edit");


        // 浮层（顶栏 + 一段管家回答）
        {
            var scr = System.Windows.Forms.Screen.PrimaryScreen ?? System.Windows.Forms.Screen.AllScreens[0];
            var ov = new OverlayWindow(m, scr, "main");
            ov.Demo(Strings.En ? "What's on my plate today?" : "我今天有什么事？",
                Strings.En ? "You have a team sync in 12 minutes, then a dentist appointment tomorrow afternoon. Three to-dos are still open: the lab report is due tomorrow." : "12 分钟后有组会，明天下午看牙。还有 3 件待办没做完，其中实验报告明天截止。");
            var oc = (UIElement)ov.Content; ov.Content = null;
            var g = new Grid { Width = 1920, Height = 1080, Background = new LinearGradientBrush(Color.FromRgb(38, 70, 120), Color.FromRgb(160, 110, 150), 35) };
            g.Children.Add(new Border { Background = m.Pal.Dim });
            g.Children.Add(oc);
            Save(g, dir, "3-overlay");
            ov.Close();
        }

        // 3) Dock
        var dock = new DockWindow(m);
        var dc = (UIElement)dock.Content; dock.Content = null;
        Save(Host(dc, 900, 120, new SolidColorBrush(Color.FromRgb(70, 90, 120))), dir, "4-dock");
        dock.Close();

        // 4) 设置各页
        foreach (var page in new[] { "general", "desktop", "dock", "mail", "calendar", "market", "ai", "about" })
        {
            if (page == "mail") store.Set("mail", new JsonObject { ["source"] = "imap", ["email"] = "someone@gmail.com", ["provider"] = "gmail" });
            var w = new SettingsWindow(m, page);
            var c = (UIElement)w.Content; w.Content = null;
            Save(Host(c, 900, 640, m.Pal.Window), dir, "5-settings-" + page);
            w.Close();
        }

        // 5) 引导各页
        Onboarding.NoAnimation = true;
        for (int i = 0; i < 5; i++)
        {
            var ob = new Onboarding(m);
            for (int k = 0; k < i; k++) ob.GoNext();
            var c = (UIElement)ob.Content; ob.Content = null;
            Save(Host(c, 760, 540, new SolidColorBrush(Color.FromRgb(90, 110, 140))), dir, "6-onboarding-" + i);
            ob.Close();
        }
    }

    static JsonObject It(string id, int col, int row, string size) => new() { ["id"] = id, ["on"] = true, ["col"] = col, ["row"] = row, ["size"] = size };

    static UIElement Desk(Model m, bool interactive, bool editing)
    {
        var g = new Grid { Width = 1920, Height = 1080 };
        g.Background = new LinearGradientBrush(Color.FromRgb(38, 70, 120), Color.FromRgb(160, 110, 150), 35);
        if (interactive) g.Children.Add(new Border { Background = m.Pal.Dim });   // 浮层的暗色底
        var grid = new GridView(m, "main", interactive);
        g.Children.Add(new Border { Child = grid, Margin = new Thickness(0, 0, 0, 120) });
        g.Measure(new Size(1920, 1080)); g.Arrange(new Rect(0, 0, 1920, 1080)); g.UpdateLayout();
        if (editing) grid.Editing = true; else grid.Rebuild();
        return g;
    }

    static UIElement Host(UIElement c, double w, double h, Brush bg) => new Border { Width = w, Height = h, Background = bg, Child = c };

    static void Save(UIElement e, string dir, string name)
    {
        var fe = (FrameworkElement)e;
        double w = double.IsNaN(fe.Width) ? 1200 : fe.Width, h = double.IsNaN(fe.Height) ? 800 : fe.Height;
        for (int i = 0; i < 3; i++) { fe.Measure(new Size(w, h)); fe.Arrange(new Rect(0, 0, w, h)); fe.UpdateLayout(); }
        var bmp = new RenderTargetBitmap((int)w, (int)h, 96, 96, PixelFormats.Pbgra32);
        bmp.Render(fe);
        var enc = new PngBitmapEncoder();
        enc.Frames.Add(BitmapFrame.Create(bmp));
        using var f = File.Create(Path.Combine(dir, name + ".png"));
        enc.Save(f);
    }

    /** 示例数据（和 Mac 版截图用的差不多，不含任何真实个人信息） */
    static void Sample(Model m)
    {
        var now = U.NowMs();
        double Min(double x) => now + x * 60000;
        foreach (var (k, name, price, pct) in new[] { ("sh000001", "上证指数", 3268.11, 0.82), ("sz399001", "深证成指", 10422.5, 1.15), ("rt_hkHSI", "恒生指数", 23909.63, -1.15), ("gb_ixic", "纳斯达克", 18342.9, 0.36), ("gb_inx", "标普500", 5871.2, -0.21), ("rt_hk00700", "腾讯控股", 512.5, 2.4), ("gb_aapl", "苹果", 242.9, -0.15), ("gb_nvda", "英伟达", 139.4, 3.1) })
            m.Quotes[k] = new Quote { Key = k, Code = Market.DisplayCode(k), Market = Market.MarketOf(k), Name = Strings.En ? Market.DisplayCode(k) : name, Price = price, Pct = pct };
        m.NewsItems = new List<NewsItem>
        {
            new(Strings.En ? "Fed signals patience as inflation cools" : "美联储释放耐心信号，通胀继续降温", "https://example.com/1", Min(-12), "", "财经", "BBC"),
            new(Strings.En ? "New chip export rules take effect next month" : "芯片出口新规下月生效", "https://example.com/2", Min(-40), "", "科技", "CNBC"),
            new(Strings.En ? "City opens three new metro lines" : "地铁三条新线今天开通", "https://example.com/3", Min(-95), "", "本地", "RTHK"),
            new(Strings.En ? "Hong Kong stocks slip in afternoon trade" : "港股下午初段跌逾1%", "https://example.com/4", Min(-130), "", "财经", "RTHK"),
            new(Strings.En ? "Researchers unveil faster battery chemistry" : "研究人员公布更快充电的电池技术", "https://example.com/5", Min(-200), "", "科技", "sspai"),
        };
        var city = Model.CityKey(m.Store.City);
        m.Weathers[city] = new Weather(Strings.En ? "Shanghai" : "上海", now, new WxNow(21, 20, 62, 9, "多云", "sun-cloud"), new List<WxDay>
        {
            new(DateTime.Today.ToString("yyyy-MM-dd"), 24, 16, 20, "多云", "sun-cloud"), new(DateTime.Today.AddDays(1).ToString("yyyy-MM-dd"), 22, 15, 70, "小雨", "rain"),
            new(DateTime.Today.AddDays(2).ToString("yyyy-MM-dd"), 25, 17, 10, "晴", "sun"), new(DateTime.Today.AddDays(3).ToString("yyyy-MM-dd"), 23, 16, 30, "阴", "cloud"),
        });
        m.Events = new List<CalEvent>
        {
            new("1", Strings.En ? "Team sync" : "组会", Min(12), Min(72), false, "", ""),
            new("2", Strings.En ? "Dentist" : "看牙", Min(60 * 26), Min(60 * 27), false, "", ""),
            new("3", Strings.En ? "Project review" : "项目评审", Min(60 * 50), Min(60 * 51), false, "", ""),
        };
        m.Store.Set("calendar", new JsonObject { ["ics"] = new JsonArray(new JsonObject { ["name"] = "Google", ["url"] = "https://calendar.google.com/x.ics" }) });
        m.Mail = new MailState
        {
            Ok = true, Unread = 4,
            Items = new List<MailItem>
            {
                new(Strings.En ? "School Registrar" : "教务处", "registrar@school.edu", Strings.En ? "Spring enrollment opens Monday" : "下学期选课周一开始", Min(-20), "imap:1", "Gmail"),
                new("GitHub", "noreply@github.com", Strings.En ? "[glancedesk] New star" : "[glancedesk] 有人点了 Star", Min(-75), "imap:2", "Gmail"),
                new(Strings.En ? "Bank" : "银行", "service@bank.com", Strings.En ? "Your monthly statement is ready" : "本月账单已出", Min(-300), "imap:3", "Gmail"),
            },
        };
        m.Store.Set("mail", new JsonObject { ["source"] = "imap", ["email"] = "someone@gmail.com" });
        m.Coins["bitcoin,cny"] = new CoinQuote("bitcoin", 482000, 1.8); m.Coins["ethereum,cny"] = new CoinQuote("ethereum", 18900, -0.6); m.Coins["solana,cny"] = new CoinQuote("solana", 1210, 4.2);
        m.Coins["bitcoin,usd"] = new CoinQuote("bitcoin", 67000, 1.8); m.Coins["ethereum,usd"] = new CoinQuote("ethereum", 2630, -0.6); m.Coins["solana,usd"] = new CoinQuote("solana", 168, 4.2);
        m.Repos[Update.Repo] = new RepoInfo(Update.Repo, 128, 9, 3, 1520);
        m.Rates["CNY"] = (new Dictionary<string, double> { ["USD"] = 0.1405, ["EUR"] = 0.1298, ["JPY"] = 21.37, ["HKD"] = 1.0921 }, now);
        m.Rates["USD"] = (new Dictionary<string, double> { ["CNY"] = 7.118, ["EUR"] = 0.924, ["JPY"] = 152.1, ["GBP"] = 0.771 }, now);
        m.Feeds["https://example.com/feed"] = (Strings.En ? "My blog" : "我的博客", m.NewsItems.Take(4).ToList());
        m.Sys = new SysStat { Cpu = 23, Mem = 61, DiskFree = 212e9, DiskTotal = 512e9, Down = 1.3e6, Up = 86e3, Battery = 78 };
        m.Playing = new NowPlaying { Title = Strings.En ? "Sunny Day" : "晴天", Artist = Strings.En ? "Jay Chou" : "周杰伦", App = "Spotify", Playing = true, Position = 84, Duration = 269, At = DateTime.UtcNow };
        m.PomoLeft = 18 * 60 + 25; m.PomoRunning = true;
        m.SaveTodos("todo", new List<TodoItem> { new() { Title = Strings.En ? "Finish lab report" : "写完实验报告", Due = DateTime.Today.AddDays(1).ToString("yyyy-MM-dd") }, new() { Title = Strings.En ? "Reply to Alex" : "回复小王" }, new() { Title = Strings.En ? "Book flight home" : "订回家的机票" } });
    }
}
