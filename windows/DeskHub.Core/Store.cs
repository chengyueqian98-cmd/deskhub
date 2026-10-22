// 设置存储：%APPDATA%\DeskHub\desk.json。键名和 Mac 版一样，所以把 Mac 的 desk.json 拷过来也能直接用。
// 密码和 API Key 不放这里（在 App 的 Secrets 里用 Windows 自带的 DPAPI 加密单独存）。
using System.Text.Encodings.Web;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace DeskHub.Core;

public class Store
{
    public readonly string Path;
    public JsonObject Data { get; private set; }
    public event Action<HashSet<string>>? Changed;

    public static string DefaultPath =>
        System.IO.Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "DeskHub", "desk.json");

    public Store(string? path = null)
    {
        Path = path ?? DefaultPath;
        JsonObject? saved = null;
        try { if (File.Exists(Path)) saved = JsonNode.Parse(File.ReadAllText(Path)) as JsonObject; } catch { }
        Data = saved ?? new JsonObject();
    }

    static readonly JsonSerializerOptions Pretty = new() { WriteIndented = true, Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping };

    public void Set(JsonObject patch)
    {
        var keys = new HashSet<string>();
        foreach (var (k, v) in patch.ToList()) { Data[k] = v?.DeepClone(); keys.Add(k); }
        Save();
        Changed?.Invoke(keys);
    }

    public void Set(string key, JsonNode? value) => Set(new JsonObject { [key] = value?.DeepClone() });

    void Save()
    {
        try
        {
            Directory.CreateDirectory(System.IO.Path.GetDirectoryName(Path)!);
            var tmp = Path + ".tmp";
            File.WriteAllText(tmp, Data.ToJsonString(Pretty));
            File.Move(tmp, Path, true);   // 先写临时文件再改名，断电也不会写坏
        }
        catch { }
    }

    // —— 带默认值的读取 ——
    public List<string> Watch => Data["watch"] is JsonArray ? U.Strs(Data["watch"]) : Market.DefaultWatch.ToList();
    public string Colors => U.Str(Data["colors"]) ?? "mono";
    public double AlertPct => U.Num(Data["alertPct"]) ?? 3;
    public (string name, double lat, double lon) City =>
        Data["city"] is JsonObject c && U.Num(c["lat"]) is double lat && U.Num(c["lon"]) is double lon ? (U.Str(c["name"]) ?? "", lat, lon) : (I18n.L(WeatherApi.DefaultCity.name), WeatherApi.DefaultCity.lat, WeatherApi.DefaultCity.lon);
    public JsonNode? Layout => Data["layout"];
    public string ButlerName { get { var n = (U.Str(Data["butlerName"]) ?? "").Trim(); return n == "" ? I18n.L("管家") : n; } }
    public List<string> NewsSources => Data["newsSources"] is JsonArray ? U.Strs(Data["newsSources"]) : News.DefaultIds;
    public bool Onboarded => U.Bool(Data["onboarded"]) == true;
    public string Lang => U.Str(Data["lang"]) == "en" ? "en" : "zh";
    /** auto 跟系统 / light / dark */
    public string Theme => U.Str(Data["theme"]) ?? "auto";
    public string Accent => U.Str(Data["accent"]) ?? "blue";
    public JsonObject Mail => U.Obj(Data["mail"]);
    public JsonObject Win => U.Obj(Data["win"]);
    public bool WinFlag(string k, bool dflt) => U.Bool(Win[k]) ?? dflt;
    public void SetWin(string k, JsonNode? v) { var w = (JsonObject)Win.DeepClone(); w[k] = v?.DeepClone(); Set("win", w); }

    public List<string> MailContacts => U.Strs(U.Obj(Data["butlerRules"])["contacts"]);

    /** 每个组件自己的设置：{ 组件 id: {...} } */
    public JsonObject Config(string id) => U.Obj(U.Obj(Data["widgetConfig"])[id]).DeepClone().AsObject();
    public void SetConfig(string id, JsonObject c)
    {
        var all = (JsonObject)U.Obj(Data["widgetConfig"]).DeepClone();
        all[id] = c.DeepClone();
        Set("widgetConfig", all);
    }

    // —— 日程设置 ——
    public List<(string name, string url)> IcsList =>
        (Data["calendar"]?["ics"] as JsonArray ?? new JsonArray())
        .Select(x => (U.Str(x?["name"]) ?? "", U.Str(x?["url"]) ?? "")).Where(x => x.Item2 != "").ToList();
    public int SoonMin => (int)(U.Num(Data["calendar"]?["soonMin"]) ?? 15);
    /** 1 = 周一开头，0 = 周日开头 */
    public int WeekStart => (int)(U.Num(Data["calendar"]?["weekStart"]) ?? (Strings.En ? 0 : 1));

    // —— 多屏：每块屏幕一份布局（主屏用 layout，其它屏用 screenLayouts[屏幕名]） ——
    public JsonNode? LayoutFor(string key) => key == "main" ? Data["layout"] : U.Obj(Data["screenLayouts"])[key];
    public void SetLayout(string key, JsonObject l)
    {
        if (key == "main") { Set("layout", l); return; }
        var all = (JsonObject)U.Obj(Data["screenLayouts"]).DeepClone();
        all[key] = l.DeepClone();
        Set("screenLayouts", all);
    }
}
