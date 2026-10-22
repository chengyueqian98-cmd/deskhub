// 首次打开的引导：像苹果新设备开机那样一页一件事——语言、你是谁、城市、桌面怎么用、完成。
using System;
using System.Linq;
using System.Text.Json.Nodes;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Media.Imaging;
using DeskHub.Core;
using static DeskHub.Core.I18n;

namespace DeskHub;

public class Onboarding : Window
{
    readonly Model m;
    int pageNo;
    string persona = "student";
    bool showDock = true, hideIcons, autoStart = true;
    readonly ContentControl host = new();
    public Action? Done;

    public Onboarding(Model m)
    {
        this.m = m;
        Width = 760; Height = 540;
        WindowStyle = WindowStyle.None;
        AllowsTransparency = true;
        Background = Brushes.Transparent;
        ResizeMode = ResizeMode.NoResize;
        WindowStartupLocation = WindowStartupLocation.CenterScreen;
        FontFamily = UI.Font;
        Title = "Glancedesk";
        Content = new Border { CornerRadius = new CornerRadius(22), Background = m.Pal.Window, BorderBrush = m.Pal.CardBorder, BorderThickness = new Thickness(1), Child = host, Margin = new Thickness(20), Effect = UI.Shadow(40, 0.35) };
        MouseLeftButtonDown += (_, e) => { if (e.ButtonState == MouseButtonState.Pressed) try { DragMove(); } catch { } };
        Draw();
    }

    Palette P => m.Pal;

    void Next() { pageNo++; Draw(); }
    public void GoNext() => Next();
    void Back() { if (pageNo > 0) { pageNo--; Draw(); } }

    public static bool NoAnimation;   // 截图时不要淡入（不然截到的是透明的）

    void Draw()
    {
        var page = pageNo switch { 0 => Welcome(), 1 => Persona(), 2 => City(), 3 => Desktop(), _ => Finish() };
        host.Content = page;
        if (NoAnimation) return;
        page.Opacity = 0;
        page.BeginAnimation(OpacityProperty, new DoubleAnimation(0, 1, TimeSpan.FromMilliseconds(220)));
    }

    /** 一页：标题、说明、内容、底部按钮 */
    Grid Page(string title, string sub, UIElement? body, string next = "", Action? onNext = null, bool back = true)
    {
        var g = new Grid { Margin = new Thickness(56, 46, 56, 34) };
        g.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        g.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
        g.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        var head = UI.V(10, Center(UI.T(title, 30, P.Text, FontWeights.SemiBold, UI.Display)), Center(UI.Wrap(sub, 14.5, P.Text2)));
        ((TextBlock)head.Children[1]).TextAlignment = TextAlignment.Center;
        g.Children.Add(head);
        if (body != null) { Grid.SetRow(body, 1); if (body is FrameworkElement f) { f.VerticalAlignment = VerticalAlignment.Center; f.HorizontalAlignment = HorizontalAlignment.Center; } g.Children.Add(body); }
        var btns = new Grid();
        if (back && pageNo > 0) { var b = UI.Pill(L("返回"), P, Back); b.HorizontalAlignment = HorizontalAlignment.Left; btns.Children.Add(b); }
        var n = UI.Pill(next == "" ? L("继续") : next, P, onNext ?? Next, true, 14);
        n.HorizontalAlignment = HorizontalAlignment.Center; n.MinWidth = 180;
        btns.Children.Add(n);
        Grid.SetRow(btns, 2);
        g.Children.Add(btns);
        return g;
    }

    static FrameworkElement Center(FrameworkElement e) { e.HorizontalAlignment = HorizontalAlignment.Center; return e; }

    Border Option(string title, string sub, bool on, Action pick, double width = 150)
    {
        var b = new Border
        {
            Width = width, Padding = new Thickness(14, 12, 14, 12), Margin = new Thickness(6), CornerRadius = new CornerRadius(14), Cursor = Cursors.Hand,
            Background = on ? P.Fill2 : P.Fill, BorderBrush = on ? P.AccentB : Brushes.Transparent, BorderThickness = new Thickness(2),
            Child = UI.V(4, UI.T(title, 15, P.Text, FontWeights.SemiBold), UI.Wrap(sub, 12, P.Text2)),
        };
        b.MouseLeftButtonUp += (_, _) => { pick(); Draw(); };
        return b;
    }

    UIElement Welcome()
    {
        Image? icon = null;
        try { icon = new Image { Source = BitmapFrame.Create(new Uri("pack://application:,,,/icon.png")), Width = 96, Height = 96 }; } catch { }
        var lang = UI.H(0, Option("中文", "简体中文", Strings.Lang == "zh", () => SetLang("zh")), Option("English", "English", Strings.Lang == "en", () => SetLang("en")));
        var body = UI.V(26, icon, lang);
        var g = Page(L("一瞥"), L("把时间、天气、日程、邮件和行情放到桌面上。安静地待在图标后面，需要时按一下就出来。"), body, back: false);
        return g;
    }

    void SetLang(string l) { m.Store.Set("lang", l); Strings.Lang = l; }

    UIElement Persona()
    {
        var opts = new[] { ("student", L("学生"), L("课表、待办、倒数日")), ("work", L("上班"), L("邮件、日程、世界时钟")), ("invest", L("投资"), L("行情、新闻、加密货币")), ("minimal", L("极简"), L("只要时间和天气")) };
        var wrap = new WrapPanel { HorizontalAlignment = HorizontalAlignment.Center };
        foreach (var (id, t, s) in opts) { var pid = id; wrap.Children.Add(Option(t, s, persona == id, () => persona = pid, 136)); }
        return Page(L("你主要用电脑做什么？"), L("先给你摆一套合适的组件，之后随时可以加、删、拖动。"), wrap);
    }

    UIElement City()
    {
        var q = new TextBox { Width = 280, FontSize = 15, Padding = new Thickness(12, 7, 12, 7), Foreground = P.Text, Background = P.Fill, BorderBrush = P.CardBorder, CaretBrush = P.Text };
        var results = new StackPanel { HorizontalAlignment = HorizontalAlignment.Center };
        var cur = UI.T(L("现在：") + m.Store.City.name, 13, P.Text3);
        async void Search()
        {
            results.Children.Clear();
            try
            {
                foreach (var x in WeatherApi.ParseSearch(await Net.Json(WeatherApi.SearchUrl(q.Text.Trim(), Strings.En ? "en" : "zh"))).Take(5))
                {
                    var hit = x;
                    var p = UI.Pill($"{x.name}  ·  {x.region}", P, () => { m.Store.Set("city", new JsonObject { ["name"] = hit.name, ["lat"] = hit.lat, ["lon"] = hit.lon }); cur.Text = L("现在：") + hit.name; results.Children.Clear(); });
                    p.Margin = new Thickness(0, 4, 0, 0);
                    results.Children.Add(p);
                }
            }
            catch { results.Children.Add(UI.T(L("搜索失败，检查一下网络"), 12, P.Text3)); }
        }
        q.KeyDown += (_, e) => { if (e.Key == System.Windows.Input.Key.Enter) Search(); };
        var body = UI.V(10, UI.H(8, q, UI.Pill(L("搜索"), P, Search)), Center(cur), results);
        return Page(L("你在哪个城市？"), L("用来显示天气。输入城市名按回车。"), body);
    }

    UIElement Desktop()
    {
        UIElement Row(string title, string sub, bool on, Action<bool> set)
        {
            var c = new CheckBox { IsChecked = on, VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(0, 0, 12, 0) };
            c.Checked += (_, _) => set(true); c.Unchecked += (_, _) => set(false);
            var r = UI.H(0, c, UI.V(2, UI.T(title, 14.5, P.Text, FontWeights.SemiBold), UI.T(sub, 12, P.Text2)));
            r.Margin = new Thickness(0, 8, 0, 8);
            return r;
        }
        var body = UI.V(4,
            Row(L("显示底部 Dock"), L("放常用的应用和文件，可以收起来"), showDock, v => showDock = v),
            Row(L("清空桌面（隐藏桌面图标）"), L("只是藏起来，随时可以在设置里放回来"), hideIcons, v => hideIcons = v),
            Row(L("开机自动启动"), L("开机后组件就在桌面上"), autoStart, v => autoStart = v));
        return Page(L("你的桌面"), L("组件在桌面图标后面，不挡任何窗口。"), body);
    }

    UIElement Finish()
    {
        var keys = UI.H(8, KeyCap("Ctrl"), UI.T("+", 18, P.Text3), KeyCap("Alt"), UI.T("+", 18, P.Text3), KeyCap(L("空格")));
        var body = UI.V(14, Center(keys), Center(UI.T(L("随时按这组键呼出浮层：组件可以点、可以拖动编辑，还能问管家问题"), 13.5, P.Text2)));
        return Page(L("准备好了"), L("以后在任务栏右下角的图标里也能打开浮层和设置。"), body, L("开始使用"), Finish2);
    }

    Border KeyCap(string k) => new() { Background = P.Fill2, CornerRadius = new CornerRadius(8), Padding = new Thickness(14, 6, 14, 7), Child = UI.T(k, 16, P.Text, FontWeights.SemiBold) };

    void Finish2()
    {
        var s = m.Store;
        s.Set(new JsonObject { ["layout"] = Layouts.PresetLayout(persona), ["onboarded"] = true });
        if (persona == "student" && s.Config("countdown").Count == 0)
            s.SetConfig("countdown", new JsonObject { ["items"] = new JsonArray(new JsonObject { ["title"] = L("期末考试"), ["date"] = DateTime.Today.AddDays(45).ToString("yyyy-MM-dd") }) });
        s.SetWin("dock", showDock);
        s.SetWin("hideIcons", hideIcons);
        AutoStart.Enabled = autoStart;
        Close();
        Done?.Invoke();
    }
}
