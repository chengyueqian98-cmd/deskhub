// 桌面网格布局（和 Mac 版 Sources/Core/Layout.swift 规则一条不改，存盘格式一样）。
//
// 像苹果小组件那样按「小 / 中 / 大」几档摆，松手吸附，永不重叠，并且会自动避让、自动复位：
//   S 小 1×1 · M 中 2×1 · L 大 2×2 · T 高 2×3 · W 宽 4×1 · XL 特大 4×2
// 一屏 8 列 × 4 行。每个组件记着现在的位置 col/row、原位 hc/hr、最近被动过的先后 pri。
using System.Text.Json.Nodes;
using static DeskHub.Core.I18n;

namespace DeskHub.Core;

public static class DeskGrid
{
    public const int Cols = 8, Rows = 4, Version = 4;
    public const double Gap = 16, CellMin = 120, CellMax = 260, RowMin = 110, RowMax = 300;
}

public record SizeSpec(int W, int H, string Label);

public record WidgetDef(string Id, string Label, string Size, string[] Sizes, bool Multi = false, string LabelEn = "", bool WinOnly = false)
{
    public string Name => Strings.En && LabelEn != "" ? LabelEn : Label;
}

public class LayoutItem
{
    public string Id = "", Type = "", Size = "M", Name = "";
    public bool On;
    public int Col, Row, Hc, Hr, W, H;
    public double Pri;

    public LayoutItem Copy() => (LayoutItem)MemberwiseClone();

    public JsonObject Json => new()
    {
        ["id"] = Id, ["type"] = Type, ["on"] = On, ["col"] = Col, ["row"] = Row, ["hc"] = Hc, ["hr"] = Hr,
        ["pri"] = Pri, ["size"] = Size, ["w"] = W, ["h"] = H, ["name"] = Name,
    };
}

public class Layout
{
    public List<LayoutItem> Items = new();
    public LayoutItem? Item(string id) => Items.FirstOrDefault(i => i.Id == id);
    public JsonObject Json => new() { ["version"] = DeskGrid.Version, ["cols"] = DeskGrid.Cols, ["items"] = new JsonArray(Items.Select(i => (JsonNode)i.Json).ToArray()) };
}

public readonly record struct Metrics(double CellW, double RowH, double Gap);
public readonly record struct CellRect(double Left, double Top, double Width, double Height);

public static class Layouts
{
    public static readonly Dictionary<string, SizeSpec> Sizes = new()
    {
        ["S"] = new(1, 1, "小"), ["M"] = new(2, 1, "中"), ["L"] = new(2, 2, "大"),
        ["T"] = new(2, 3, "高"), ["W"] = new(4, 1, "宽"), ["XL"] = new(4, 2, "特大"),
    };

    /** 组件登记表：sizes 是允许的档位，size 是默认档。id 就是组件的「种类」 */
    public static readonly WidgetDef[] Widgets =
    {
        new("clock", "时钟", "M", new[] { "S", "M" }, LabelEn: "Clock"),
        new("butler", "管家", "M", new[] { "M", "L", "W" }, LabelEn: "Butler"),
        new("weather", "天气", "M", new[] { "S", "M" }, true, "Weather"),
        new("market", "行情", "L", new[] { "M", "L", "T" }, true, "Stocks"),
        new("calendar", "日历", "L", new[] { "L", "T" }, LabelEn: "Calendar"),
        new("mail", "邮件", "M", new[] { "M", "L", "T" }, LabelEn: "Mail"),
        new("news", "新闻", "L", new[] { "M", "L", "T" }, LabelEn: "News"),
        new("worldclock", "世界时钟", "M", new[] { "S", "M" }, true, "World Clock"),
        new("risk", "风控", "M", new[] { "M", "L" }, LabelEn: "Risk"),
        new("todo", "待办", "L", new[] { "M", "L", "T" }, true, "To-dos"),
        new("countdown", "倒数日", "M", new[] { "S", "M", "L" }, true, "Countdown"),
        new("crypto", "加密货币", "M", new[] { "M", "L" }, true, "Crypto"),
        new("github", "GitHub", "M", new[] { "M", "L" }, true, "GitHub"),
        new("rss", "订阅", "L", new[] { "M", "L", "T" }, true, "Feed"),
        new("photo", "照片", "L", new[] { "S", "M", "L", "T", "W", "XL" }, true, "Photos"),
        new("pomodoro", "番茄钟", "S", new[] { "S", "M" }, LabelEn: "Focus Timer"),
        new("sysstat", "系统状态", "M", new[] { "S", "M", "L" }, LabelEn: "System"),
        new("note", "便签", "M", new[] { "S", "M", "L", "T" }, true, "Note"),
        new("fx", "汇率", "M", new[] { "S", "M", "L" }, true, "Exchange Rates"),
        new("lunar", "农历节日", "S", new[] { "S", "M" }, LabelEn: "Lunar & Holidays"),
        new("nowplaying", "正在播放", "M", new[] { "M", "W" }, LabelEn: "Now Playing"),
    };

    /** Windows 版不提供的组件（风控要读 Mac 上的量化系统文件）：布局里保留，但不显示、不能加 */
    public static readonly HashSet<string> Hidden = new() { "risk" };

    public static WidgetDef? Def(string type) => Widgets.FirstOrDefault(w => w.Id == type);

    /** 实例 id → 种类：「market」「market-2」都是行情 */
    public static string TypeOf(string id)
    {
        if (Def(id) != null) return id;
        int i = id.LastIndexOf('-');
        if (i > 0 && Def(id[..i]) != null && int.TryParse(id[(i + 1)..], out _)) return id[..i];
        return id;
    }

    static readonly (string id, bool on, int col, int row, string size)[] Defaults =
    {
        ("clock", true, 0, 0, "M"), ("butler", true, 0, 1, "M"), ("market", true, 0, 2, "L"),
        ("weather", true, 6, 0, "M"), ("calendar", true, 6, 1, "L"), ("mail", true, 6, 3, "M"),
        ("news", false, 2, 0, "L"), ("worldclock", false, 4, 3, "M"), ("risk", false, 4, 2, "M"),
    };

    static JsonObject DefaultItem(string id)
    {
        foreach (var d in Defaults) if (d.id == id) return new JsonObject { ["id"] = d.id, ["on"] = d.on, ["col"] = d.col, ["row"] = d.row, ["size"] = d.size };
        return new JsonObject { ["id"] = id, ["size"] = Def(id)!.Size };
    }

    static bool HasDefault(string id) => Defaults.Any(d => d.id == id);

    static int ClampInt(JsonNode? v, int lo, int hi, int dflt)
    {
        var d = U.Num(v);
        if (d == null) return dflt;
        return Math.Min(hi, Math.Max(lo, (int)Math.Round(d.Value, MidpointRounding.AwayFromZero)));
    }

    /** 组件的尺寸（格）。档位不在允许范围内就退回默认档 */
    public static (string size, int w, int h) Dims(string id, string? size)
    {
        var def = Def(id);
        var key = def == null ? "M" : (size != null && def.Sizes.Contains(size) ? size : def.Size);
        var s = Sizes[key];
        return (key, s.W, s.H);
    }

    static LayoutItem? Norm1(JsonNode? raw)
    {
        if (raw is not JsonObject o || U.Str(o["id"]) is not string id) return null;
        var type = TypeOf(id);
        var def = Def(type);
        if (def == null || (id != type && !def.Multi)) return null;
        var d = Dims(type, U.Str(o["size"]));
        int col = ClampInt(o["col"], 0, DeskGrid.Cols - d.w, 0), row = ClampInt(o["row"], 0, 200, 0);
        return new LayoutItem
        {
            Id = id, Type = type, On = U.Bool(o["on"]) != false, Col = col, Row = row,
            Hc = ClampInt(o["hc"], 0, DeskGrid.Cols - d.w, col), Hr = ClampInt(o["hr"], 0, 200, row),
            Pri = U.Num(o["pri"]) ?? 0, Size = d.size, W = d.w, H = d.h, Name = (U.Str(o["name"]) ?? "").Head(20),
        };
    }

    public static bool Overlaps((int col, int row, int w, int h) a, (int col, int row, int w, int h) b) =>
        a.col < b.col + b.w && b.col < a.col + a.w && a.row < b.row + b.h && b.row < a.row + a.h;

    static (int, int, int, int) Box(LayoutItem i) => (i.Col, i.Row, i.W, i.H);
    static bool Hits(List<LayoutItem> placed, (int, int, int, int) b) => placed.Any(p => p.On && Overlaps(b, Box(p)));

    static (int col, int row)? NearestSlot(List<LayoutItem> placed, int w, int h, int col, int row)
    {
        (int col, int row, int dist)? best = null;
        for (int r = 0; r + h <= DeskGrid.Rows; r++)
            for (int c = 0; c + w <= DeskGrid.Cols; c++)
                if (!Hits(placed, (c, r, w, h)))
                {
                    int dist = Math.Abs(c - col) + Math.Abs(r - row);
                    if (best == null || dist < best.Value.dist) best = (c, r, dist);
                }
        return best == null ? null : (best.Value.col, best.Value.row);
    }

    static int PushDown(List<LayoutItem> placed, int w, int h, int col, int row)
    {
        int r = Math.Max(0, row);
        for (int k = 0; k < 400; k++)
        {
            var hit = placed.FirstOrDefault(p => p.On && Overlaps((col, r, w, h), Box(p)));
            if (hit == null) return r;
            r = hit.Row + hit.H;
        }
        return r;
    }

    /** 把整份布局修成合法的：补齐缺的组件、夹住越界，然后按优先级逐个摆放 */
    public static Layout Normalize(JsonNode? layout, string? priority = null)
    {
        var obj = layout as JsonObject;
        var src = obj?["items"] as JsonArray ?? new JsonArray();
        var legacy = src.Count > 0 && (int)(U.Num(obj?["version"]) ?? -1) != DeskGrid.Version;
        var first = src.Count == 0;
        var byId = new Dictionary<string, LayoutItem>();
        var extras = new List<LayoutItem>();
        foreach (var it in src)
        {
            var n = Norm1(it);
            if (n == null) continue;
            if (n.Id == n.Type) byId[n.Id] = n;
            else if (!legacy && !extras.Any(e => e.Id == n.Id)) extras.Add(n);
        }
        var items = new List<LayoutItem>();
        foreach (var def in Widgets)
        {
            byId.TryGetValue(def.Id, out var got);
            if (got != null && !legacy) { items.Add(got); continue; }
            if (got != null && legacy)
            {
                var dd = DefaultItem(def.Id);
                dd["name"] = got.Name;
                var m = Norm1(dd)!;
                m.On = got.On;
                items.Add(m);
                continue;
            }
            var n = Norm1(DefaultItem(def.Id))!;
            n.Name = "";
            if (!(first && HasDefault(def.Id))) n.On = false;
            items.Add(n);
        }
        return Place(items.Concat(extras).ToList(), priority);
    }

    static Layout Place(List<LayoutItem> items, string? priority)
    {
        var order = items.Select((x, i) => (i, x)).ToList();
        order.Sort((a, b) =>
        {
            var (ia, x) = a; var (ib, y) = b;
            if (x.Id != y.Id)
            {
                if (x.Id == priority) return -1;
                if (y.Id == priority) return 1;
            }
            if (x.Pri != y.Pri) return x.Pri > y.Pri ? -1 : 1;
            if (x.Hr != y.Hr) return x.Hr.CompareTo(y.Hr);
            if (x.Hc != y.Hc) return x.Hc.CompareTo(y.Hc);
            return ia.CompareTo(ib);
        });
        var placed = new List<LayoutItem>();
        foreach (var (_, orig) in order)
        {
            var it = orig.Copy();
            int hc = Math.Min(it.Hc, DeskGrid.Cols - it.W), hr = Math.Min(it.Hr, Math.Max(0, DeskGrid.Rows - it.H));
            if (!it.On) { it.Col = hc; it.Row = hr; placed.Add(it); continue; }
            if (!Hits(placed, (hc, hr, it.W, it.H))) { it.Col = hc; it.Row = hr; }
            else if (NearestSlot(placed, it.W, it.H, hc, hr) is var (nc, nr)) { it.Col = nc; it.Row = nr; }
            else { it.Col = hc; it.Row = PushDown(placed, it.W, it.H, hc, hr); }
            placed.Add(it);
        }
        return new Layout { Items = items.Select(i => placed.First(p => p.Id == i.Id)).ToList() };
    }

    static double NextPri(Layout l) => (l.Items.Count == 0 ? 0 : l.Items.Max(i => i.Pri)) + 1;

    /** 拖动：挪到 (col,row)，它拿到最高优先级，新位置成为原位；撞到的组件就近让开 */
    public static Layout Move(JsonNode? layout, string id, int col, int row)
    {
        var l = Normalize(layout);
        var it = l.Item(id);
        if (it == null) return l;
        var pri = NextPri(l);
        it.Col = Math.Min(DeskGrid.Cols - it.W, Math.Max(0, col));
        it.Row = Math.Min(Math.Max(0, DeskGrid.Rows - it.H), Math.Max(0, row));
        it.Hc = it.Col; it.Hr = it.Row; it.On = true; it.Pri = pri;
        return Normalize(l.Json, id);
    }

    /** 换档：只能换成允许的档位 */
    public static Layout SetSize(JsonNode? layout, string id, string size)
    {
        var l = Normalize(layout);
        var it = l.Item(id);
        if (it == null || Def(it.Type) is not WidgetDef def || !def.Sizes.Contains(size)) return l;
        var pri = NextPri(l);
        var d = Dims(def.Id, size);
        it.Size = d.size; it.W = d.w; it.H = d.h;
        it.Col = Math.Min(it.Col, DeskGrid.Cols - it.W);
        it.Row = Math.Min(it.Row, Math.Max(0, DeskGrid.Rows - it.H));
        it.Hc = it.Col; it.Hr = it.Row; it.On = true; it.Pri = pri;
        return Normalize(l.Json, id);
    }

    static (int col, int row)? SlotFor(List<LayoutItem> items, string me, int w, int h)
    {
        var others = items.Where(i => i.Id != me && i.On).ToList();
        for (int row = 0; row + h <= DeskGrid.Rows; row++)
            for (int col = 0; col + w <= DeskGrid.Cols; col++)
                if (!others.Any(o => Overlaps((col, row, w, h), Box(o)))) return (col, row);
        return null;
    }

    /** 开关一个组件。打开时先找一屏里的空位；一屏已经铺满就把「高」收成「大」腾出一行，再找一次 */
    public static Layout Toggle(JsonNode? layout, string id, bool on)
    {
        var l = Normalize(layout);
        var it = l.Item(id);
        if (it == null) return l;
        it.On = on;
        if (on)
        {
            var spot = SlotFor(l.Items, id, it.W, it.H);
            if (spot == null && l.Items.Any(i => i.On && i.Size == "T"))
            {
                foreach (var k in l.Items.Where(i => i.On && i.Size == "T")) { k.Size = "L"; k.W = Sizes["L"].W; k.H = Sizes["L"].H; }
                spot = SlotFor(l.Items, id, it.W, it.H);
            }
            if (spot is var (c, r)) { it.Col = c; it.Row = r; it.Hc = c; it.Hr = r; }
            it.Pri = NextPri(l);
        }
        return Normalize(l.Json);
    }

    /** 再加一个同种的组件（只有 multi 的能加）：新 id 是「种类-数字」 */
    public static (Layout layout, string? id) AddInstance(JsonNode? layout, string type)
    {
        var l = Normalize(layout);
        if (Def(type) is not WidgetDef def || !def.Multi) return (l, null);
        int n = 2;
        while (l.Items.Any(i => i.Id == $"{type}-{n}")) n++;
        var id = $"{type}-{n}";
        var d = Dims(type, def.Size);
        l.Items.Add(new LayoutItem { Id = id, Type = type, On = false, Size = d.size, W = d.w, H = d.h });
        return (Toggle(l.Json, id, true), id);
    }

    /** 去掉一个组件：加出来的那些直接删掉，每种的第一个只是收起 */
    public static Layout RemoveInstance(JsonNode? layout, string id)
    {
        var l = Normalize(layout);
        if (id == TypeOf(id)) return Toggle(l.Json, id, false);
        l.Items.RemoveAll(i => i.Id == id);
        return Normalize(l.Json);
    }

    /** 首次引导里的四种身份 → 一份默认布局 */
    public static JsonObject PresetLayout(string persona)
    {
        (string, int, int, string)[] cols = persona switch
        {
            "student" => new[] { ("clock", 0, 0, "M"), ("butler", 0, 1, "M"), ("todo", 0, 2, "L"), ("weather", 6, 0, "M"), ("calendar", 6, 1, "L"), ("countdown", 6, 3, "M") },
            "work" => new[] { ("clock", 0, 0, "M"), ("butler", 0, 1, "M"), ("mail", 0, 2, "L"), ("weather", 6, 0, "M"), ("calendar", 6, 1, "L"), ("worldclock", 6, 3, "M") },
            "invest" => new[] { ("clock", 0, 0, "M"), ("butler", 0, 1, "M"), ("market", 0, 2, "L"), ("weather", 6, 0, "M"), ("news", 6, 1, "L"), ("crypto", 6, 3, "M") },
            _ => new[] { ("clock", 0, 0, "M"), ("butler", 0, 1, "M"), ("weather", 6, 0, "M") },
        };
        var arr = new JsonArray();
        foreach (var c in cols) arr.Add(new JsonObject { ["id"] = c.Item1, ["on"] = true, ["col"] = c.Item2, ["row"] = c.Item3, ["size"] = c.Item4 });
        foreach (var w in Widgets.Where(w => !cols.Any(c => c.Item1 == w.Id)))
            arr.Add(new JsonObject { ["id"] = w.Id, ["on"] = false, ["col"] = 2, ["row"] = 0, ["size"] = w.Size });
        return Normalize(new JsonObject { ["version"] = DeskGrid.Version, ["items"] = arr }).Json;
    }

    public static Layout Rename(JsonNode? layout, string id, string name)
    {
        var l = Normalize(layout);
        if (l.Item(id) is LayoutItem it) it.Name = name.Head(20);
        return l;
    }

    public static List<LayoutItem> Visible(JsonNode? layout) => Normalize(layout).Items.Where(i => i.On && !Hidden.Contains(i.Type)).ToList();

    /** 网格 → 像素。宽度按屏宽算；给了高度就让 4 行正好铺满 */
    public static Metrics MetricsFor(double areaW, double? areaH = null)
    {
        var raw = (areaW - DeskGrid.Gap * (DeskGrid.Cols + 1)) / DeskGrid.Cols;
        var cellW = Math.Min(DeskGrid.CellMax, Math.Max(DeskGrid.CellMin, raw));
        var rowH = areaH is double h ? Math.Min(DeskGrid.RowMax, Math.Max(DeskGrid.RowMin, (h - DeskGrid.Gap * (DeskGrid.Rows + 1)) / DeskGrid.Rows)) : cellW;
        return new Metrics(cellW, rowH, DeskGrid.Gap);
    }

    public static CellRect ToRect(int col, int row, int w, int h, double areaW, double? areaH = null)
    {
        var m = MetricsFor(areaW, areaH);
        return new CellRect(
            Math.Round(m.Gap + col * (m.CellW + m.Gap)), Math.Round(m.Gap + row * (m.RowH + m.Gap)),
            Math.Round(w * m.CellW + (w - 1) * m.Gap), Math.Round(h * m.RowH + (h - 1) * m.Gap));
    }

    /** 像素 → 最近的格（拖动松手时用） */
    public static (int col, int row) FromPoint(double left, double top, double areaW, double? areaH = null)
    {
        var m = MetricsFor(areaW, areaH);
        return (Math.Min(DeskGrid.Cols - 1, Math.Max(0, (int)Math.Round((left - m.Gap) / (m.CellW + m.Gap), MidpointRounding.AwayFromZero))),
                Math.Max(0, (int)Math.Round((top - m.Gap) / (m.RowH + m.Gap), MidpointRounding.AwayFromZero)));
    }

    public static string SizeLabel(string key) => L(Sizes.TryGetValue(key, out var s) ? s.Label : key);
}
