// 每个组件自己的设置（编辑时卡片右上角的齿轮）。同一种可以加好几个，各看各的；存在 desk.json 的 widgetConfig[组件 id]。
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.Json.Nodes;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using DeskHub.Core;
using static DeskHub.Core.I18n;

namespace DeskHub;

public class ConfigPanel : StackPanel
{
    readonly Model m;
    readonly string id, key;
    readonly JsonObject c;
    readonly Action close;
    readonly TextBox name;
    Palette P => m.Pal;

    public ConfigPanel(Model m, string key, string id, Action close)
    {
        this.m = m; this.key = key; this.id = id; this.close = close;
        c = m.Store.Config(id);
        var type = Layouts.TypeOf(id);
        var item = Layouts.Normalize(m.LayoutFor(key)).Item(id);
        Children.Add(UI.T(Layouts.Def(type)?.Name ?? id, 20, P.Text, FontWeights.SemiBold));
        name = Box(item?.Name ?? "", Layouts.Def(type)?.Name ?? "");
        Field(L("显示的名字"), name);

        switch (type)
        {
            case "market":
                Field(L("看哪些（代码，用逗号分开；留空 = 全部自选）"), ListBox("keys", "sh000001, rt_hk00700, AAPL"));
                Note(L("A 股填 6 位数字，港股填 5 位数字，美股填字母代码。"));
                break;
            case "weather":
                Field(L("城市（留空 = 设置里的那个城市）"), CityPicker());
                break;
            case "worldclock":
            {
                var on = U.Strs(c["zones"]);
                var wrap = new WrapPanel();
                foreach (var z in Widgets.Zones)
                {
                    var zid = z.id;
                    wrap.Children.Add(Chip(Strings.En ? z.en : z.zh, on.Contains(zid), sel =>
                    {
                        var cur = U.Strs(c["zones"]);
                        c["zones"] = U.Arr(sel ? cur.Append(zid) : cur.Where(x => x != zid));
                    }));
                }
                Field(L("显示哪些城市"), wrap);
                break;
            }
            case "news":
            {
                var tag = U.Str(c["tag"]) ?? "";
                var wrap = new WrapPanel();
                var chips = new List<Border>();
                foreach (var t in new[] { "", "财经", "科技", "国际", "大中华", "本地" })
                {
                    var tt = t;
                    wrap.Children.Add(Chip(t == "" ? L("全部") : L(t), tag == t, _ => { c["tag"] = tt; Rebuild(); }, single: true));
                }
                Field(L("只看这个分类（不选 = 全部）"), wrap);
                Note(L("新闻来源在「设置 → 行情与新闻」里统一选。"));
                break;
            }
            case "countdown":
                Field(L("日子"), CountdownEditor());
                break;
            case "crypto":
                Field(L("币种（简写或 CoinGecko 的 id，用逗号分开）"), ListBox("coins", "btc, eth, sol"));
                Field(L("计价"), Choice("vs", new[] { "usd", "cny", "hkd", "eur" }, Strings.En ? "usd" : "cny", v => v.ToUpperInvariant()));
                Note(L("数据来自 CoinGecko 公开接口，两分钟刷新一次，只做展示。"));
                break;
            case "github":
                Field(L("仓库（拥有者/仓库名，用逗号分开）"), ListBox("repos", "apple/swift"));
                Note(L("显示 Star、Fork、Issue 和所有安装包的下载次数（GitHub 自带的计数）。不登录每小时只能查 60 次，所以半小时刷新一次。"));
                break;
            case "rss":
                Field(L("订阅地址（RSS 或 Atom）"), StrBox("url", "https://…/feed.xml"));
                break;
            case "photo":
            {
                var folder = UI.T(m.PhotoFolder(id), 12, P.Text2);
                var pick = UI.Pill(L("选择…"), P, () =>
                {
                    using var dlg = new System.Windows.Forms.FolderBrowserDialog { SelectedPath = m.PhotoFolder(id) };
                    if (dlg.ShowDialog() == System.Windows.Forms.DialogResult.OK) { c["folder"] = dlg.SelectedPath; folder.Text = dlg.SelectedPath; }
                });
                Field(L("照片文件夹"), UI.V(6, folder, pick));
                Note(L("每半小时换一张；在浮层里点一下照片马上换。"));
                break;
            }
            case "fx":
                Field(L("基准货币"), Choice("base", FX.Names.Keys.OrderBy(x => x).ToArray(), Strings.En ? "USD" : "CNY", v => v));
                Field(L("换算成哪些（用逗号分开）"), ListBox("targets", "USD, EUR, JPY", upper: true));
                Field(L("金额"), NumBox("amount", "100"));
                Note(L("open.er-api.com 公开汇率，每天更新，仅供参考"));
                break;
            case "pomodoro":
                Field(L("一次多久"), Choice("minutes", new[] { "15", "25", "45", "60" }, "25", v => L("%@ 分钟", v), number: true));
                break;
            case "todo":
                Note(L("待办存在这台电脑上。在浮层里点圆圈就是标成已完成，在输入框里回车就是加一条。"));
                Children.Add(UI.Pill(L("清掉已完成的"), P, () => { m.SaveTodos(id, m.Todos(id).Where(t => !t.Done).ToList()); }));
                break;
            case "note":
                Note(L("在浮层里直接写，停手一秒自动保存。"));
                break;
        }

        var done = UI.Pill(L("完成"), P, Save, true);
        var row = UI.H(8, done, id != type ? UI.Pill(L("删掉这个组件"), P, () => { m.SetLayout(key, Layouts.RemoveInstance(m.LayoutFor(key), id)); close(); }) : null);
        row.Margin = new Thickness(0, 18, 0, 0);
        Children.Add(row);
    }

    void Rebuild() { } // 单选的小圆片自己会变色，不用整页重画

    void Save()
    {
        m.Store.SetConfig(id, c);
        var cur = Layouts.Normalize(m.LayoutFor(key)).Item(id)?.Name ?? "";
        if (name.Text.Trim() != cur) m.SetLayout(key, Layouts.Rename(m.LayoutFor(key), id, name.Text.Trim()));
        if (Layouts.TypeOf(id) == "pomodoro" && U.Num(c["minutes"]) is double mins && !m.PomoRunning) m.PomoReset(mins);
        m.Kick("all");
        close();
    }

    // —— 表单小部件 ——
    void Field(string label, UIElement content)
    {
        var l = UI.T(label, 12, P.Text2);
        l.TextWrapping = TextWrapping.Wrap;
        var v = UI.V(6, l, content);
        v.Margin = new Thickness(0, 14, 0, 0);
        Children.Add(v);
    }

    void Note(string text)
    {
        var t = UI.Wrap(text, 11.5, P.Text3);
        t.Margin = new Thickness(0, 8, 0, 0);
        Children.Add(t);
    }

    TextBox Box(string text, string hint) => new()
    {
        Text = text, FontSize = 13, Padding = new Thickness(8, 5, 8, 5), Foreground = P.Text, Background = P.Fill, BorderBrush = P.CardBorder, CaretBrush = P.Text, ToolTip = hint == "" ? null : hint,
    };

    TextBox StrBox(string k, string hint)
    {
        var b = Box(U.Str(c[k]) ?? "", hint);
        b.TextChanged += (_, _) => c[k] = b.Text.Trim();
        return b;
    }

    TextBox NumBox(string k, string hint)
    {
        var b = Box(U.Num(c[k]) is double d ? U.JsNum(d) : "", hint);
        b.Width = 120; b.HorizontalAlignment = HorizontalAlignment.Left;
        b.TextChanged += (_, _) => { if (double.TryParse(b.Text, out var d)) c[k] = d; else c.Remove(k); };
        return b;
    }

    /** 逗号分开的列表 ↔ 设置里的数组（行情代码会顺手转成新浪代码） */
    TextBox ListBox(string k, string hint, bool upper = false)
    {
        var b = Box(string.Join(", ", U.Strs(c[k]).Select(x => k == "keys" ? Market.DisplayCode(x) : x)), hint);
        b.TextChanged += (_, _) =>
        {
            var parts = b.Text.Split(',', '，').Select(x => x.Trim()).Where(x => x != "");
            c[k] = U.Arr(k == "keys" ? parts.Select(Market.ToSinaKey).Where(x => x != null).Select(x => x!) : upper ? parts.Select(x => x.ToUpperInvariant()) : parts);
        };
        return b;
    }

    Border Chip(string text, bool on, Action<bool> toggle, bool single = false)
    {
        var b = new Border { CornerRadius = new CornerRadius(10), Padding = new Thickness(10, 3, 10, 4), Margin = new Thickness(0, 0, 6, 6), Cursor = System.Windows.Input.Cursors.Hand };
        var t = new TextBlock { Text = text, FontSize = 12 };
        b.Child = t;
        void Paint() { b.Background = on ? P.AccentB : P.Fill2; t.Foreground = on ? Brushes.White : P.Text; }
        Paint();
        b.MouseLeftButtonUp += (_, _) =>
        {
            if (single && b.Parent is Panel parent)
                foreach (var other in parent.Children.OfType<Border>()) { other.Background = P.Fill2; if (other.Child is TextBlock ot) ot.Foreground = P.Text; }
            on = single || !on;
            Paint();
            toggle(on);
        };
        return b;
    }

    WrapPanel Choice(string k, string[] options, string dflt, Func<string, string> label, bool number = false)
    {
        var cur = number ? (U.Num(c[k]) is double d ? U.JsNum(d) : dflt) : U.Str(c[k]) ?? dflt;
        var wrap = new WrapPanel();
        foreach (var o in options)
        {
            var v = o;
            wrap.Children.Add(Chip(label(o), cur == o, _ => { if (number) c[k] = double.Parse(v); else c[k] = v; }, single: true));
        }
        return wrap;
    }

    UIElement CityPicker()
    {
        var q = Box("", L("输入城市名"));
        var results = new StackPanel();
        var curText = UI.T(c["city"] is JsonObject cc ? L("现在：") + U.Str(cc["name"]) : L("现在：") + m.Store.City.name, 12, P.Text3);
        async void Search()
        {
            results.Children.Clear();
            try
            {
                var list = WeatherApi.ParseSearch(await Net.Json(WeatherApi.SearchUrl(q.Text.Trim(), Strings.En ? "en" : "zh")));
                foreach (var x in list)
                {
                    var hit = x;
                    results.Children.Add(UI.Pill($"{x.name}  {x.region}", P, () =>
                    {
                        c["city"] = new JsonObject { ["name"] = hit.name, ["lat"] = hit.lat, ["lon"] = hit.lon };
                        curText.Text = L("现在：") + hit.name;
                        results.Children.Clear();
                    }));
                    ((FrameworkElement)results.Children[^1]).Margin = new Thickness(0, 4, 0, 0);
                    ((FrameworkElement)results.Children[^1]).HorizontalAlignment = HorizontalAlignment.Left;
                }
                if (list.Count == 0) results.Children.Add(UI.T(L("没找到这个城市"), 12, P.Text3));
            }
            catch { results.Children.Add(UI.T(L("搜索失败，检查一下网络"), 12, P.Text3)); }
        }
        q.KeyDown += (_, e) => { if (e.Key == System.Windows.Input.Key.Enter) Search(); };
        var clear = UI.Pill(L("用设置里的城市"), P, () => { c.Remove("city"); curText.Text = L("现在：") + m.Store.City.name; });
        return UI.V(6, UI.H(6, q, UI.Pill(L("搜索"), P, Search)), curText, results, clear);
    }

    UIElement CountdownEditor()
    {
        var list = new StackPanel();
        List<JsonObject> Items() => (c["items"] as JsonArray ?? new JsonArray()).OfType<JsonObject>().Select(x => (JsonObject)x.DeepClone()).ToList();
        void Put(List<JsonObject> xs) => c["items"] = new JsonArray(xs.Select(x => (JsonNode)x).ToArray());
        void Draw()
        {
            list.Children.Clear();
            var xs = Items();
            for (int i = 0; i < xs.Count; i++)
            {
                int idx = i;
                var title = Box(U.Str(xs[i]["title"]) ?? "", L("名字，比如：期末考试"));
                title.Width = 170;
                var date = new DatePicker { SelectedDate = DateTime.TryParse(U.Str(xs[i]["date"]), out var d) ? d : DateTime.Today.AddDays(30), Width = 130, Margin = new Thickness(6, 0, 0, 0) };
                title.TextChanged += (_, _) => { var all = Items(); all[idx]["title"] = title.Text; Put(all); };
                date.SelectedDateChanged += (_, _) => { var all = Items(); all[idx]["date"] = date.SelectedDate?.ToString("yyyy-MM-dd"); Put(all); };
                var del = UI.IconButton(G.Close, P, () => { var all = Items(); all.RemoveAt(idx); Put(all); Draw(); });
                var row = UI.H(4, title, date, del);
                row.Margin = new Thickness(0, 0, 0, 6);
                list.Children.Add(row);
            }
            var add = UI.Pill(L("＋ 加一个日子"), P, () => { var all = Items(); all.Add(new JsonObject { ["title"] = "", ["date"] = DateTime.Today.AddDays(30).ToString("yyyy-MM-dd") }); Put(all); Draw(); });
            add.HorizontalAlignment = HorizontalAlignment.Left;
            list.Children.Add(add);
        }
        Draw();
        return list;
    }
}
