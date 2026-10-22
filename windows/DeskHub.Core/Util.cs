// 小工具：JSON 取值、JS 风格的数字转文字、时间换算。和 Mac 版 Sources/Core/Util.swift 一一对应。
using System.Globalization;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;

namespace DeskHub.Core;

public static class U
{
    /** 任何来源的数字（JSON 数字、字符串）→ double；不是有限数就是 null。布尔值不算数字 */
    public static double? Num(JsonNode? v)
    {
        if (v is not JsonValue jv) return null;
        if (jv.TryGetValue<double>(out var d)) return double.IsFinite(d) ? d : null;
        if (jv.TryGetValue<long>(out var l)) return l;
        if (jv.TryGetValue<int>(out var i)) return i;
        if (jv.TryGetValue<decimal>(out var m)) return (double)m;
        if (jv.TryGetValue<string>(out var s) && double.TryParse(s.Trim(), NumberStyles.Float, CultureInfo.InvariantCulture, out var p)) return double.IsFinite(p) ? p : null;
        if (jv.TryGetValue<JsonElement>(out var e))
        {
            if (e.ValueKind == JsonValueKind.Number) return e.GetDouble();
            if (e.ValueKind == JsonValueKind.String && double.TryParse(e.GetString(), NumberStyles.Float, CultureInfo.InvariantCulture, out var q)) return q;
        }
        return null;
    }

    public static string? Str(JsonNode? v)
    {
        if (v is not JsonValue jv) return null;
        if (jv.TryGetValue<string>(out var s)) return s;
        if (jv.TryGetValue<JsonElement>(out var e) && e.ValueKind == JsonValueKind.String) return e.GetString();
        return null;
    }

    public static bool? Bool(JsonNode? v)
    {
        if (v is not JsonValue jv) return null;
        if (jv.TryGetValue<bool>(out var b)) return b;
        if (jv.TryGetValue<JsonElement>(out var e) && (e.ValueKind == JsonValueKind.True || e.ValueKind == JsonValueKind.False)) return e.GetBoolean();
        return null;
    }

    public static List<string> Strs(JsonNode? v) =>
        v is JsonArray a ? a.Select(Str).Where(s => s != null).Select(s => s!).ToList() : new List<string>();

    public static JsonArray Arr(IEnumerable<string> xs) => new(xs.Select(x => (JsonNode?)JsonValue.Create(x)).ToArray());

    public static JsonNode? Clone(JsonNode? n) => n?.DeepClone();

    public static JsonObject Obj(JsonNode? n) => n is JsonObject o ? o : new JsonObject();

    /** 和 JS 的 String(number) 一样：整数不带 .0，小数用最短表示 */
    public static string JsNum(double d)
    {
        if (d == Math.Round(d) && Math.Abs(d) < 1e15) return ((long)d).ToString(CultureInfo.InvariantCulture);
        return d.ToString("R", CultureInfo.InvariantCulture);
    }

    /** 保留几位小数（toFixed 再转回数字） */
    public static double Round2(double x, int digits = 2)
    {
        var p = Math.Pow(10, digits);
        return Math.Round(x * p, MidpointRounding.AwayFromZero) / p;
    }

    /** 千分位 + 固定小数位：12,345.68 */
    public static string Fixed(double x, int digits) => x.ToString("N" + digits, CultureInfo.InvariantCulture);

    public static double NowMs() => DateTimeOffset.UtcNow.ToUnixTimeMilliseconds();

    public static string Pad2(int n) => n < 10 ? "0" + n : n.ToString();

    public static string Head(this string s, int n) => s.Length <= n ? s : s[..n];

    // —— 正则（JS 的写法：test / match / matchAll / replace） ——
    public static bool Test(this string s, string pattern, RegexOptions o = RegexOptions.None) => Regex.IsMatch(s, pattern, o);

    /** 第一个匹配的各个分组（0 = 整段）；没匹配返回 null；没参与匹配的分组是 null */
    public static string?[]? Match(this string s, string pattern, RegexOptions o = RegexOptions.None)
    {
        var m = Regex.Match(s, pattern, o);
        if (!m.Success) return null;
        return m.Groups.Cast<Group>().Select(g => g.Success ? g.Value : null).ToArray();
    }

    public static List<string?[]> MatchAll(this string s, string pattern, RegexOptions o = RegexOptions.None) =>
        Regex.Matches(s, pattern, o).Select(m => m.Groups.Cast<Group>().Select(g => g.Success ? g.Value : null).ToArray()).ToList();

    public static string Rx(this string s, string pattern, string replacement, RegexOptions o = RegexOptions.None) => Regex.Replace(s, pattern, replacement, o);

    // —— 时间 ——
    public static TimeZoneInfo Zone(string id)
    {
        try { return TimeZoneInfo.FindSystemTimeZoneById(id); } catch { return TimeZoneInfo.Local; }
    }

    /** 毫秒 → 某个时区的年月日时分（wd 0 = 周日） */
    public static Ymd Ymd(double ms, TimeZoneInfo? tz = null)
    {
        var t = TimeZoneInfo.ConvertTime(DateTimeOffset.FromUnixTimeMilliseconds((long)ms), tz ?? TimeZoneInfo.Local);
        return new Ymd(t.Year, t.Month, t.Day, t.Hour, t.Minute, (int)t.DayOfWeek);
    }

    /** 本地时间 → 毫秒（月份从 1 开始，日可以越界，像 JS 的 new Date(y, m, d) 那样自动进位） */
    public static double LocalMs(int y, int m, int d, int h = 0, int mi = 0, int s = 0) => ZoneMs(TimeZoneInfo.Local, y, m, d, h, mi, s);

    public static double ZoneMs(TimeZoneInfo tz, int y, int m, int d, int h = 0, int mi = 0, int s = 0)
    {
        var local = new DateTime(y, 1, 1, 0, 0, 0, DateTimeKind.Unspecified).AddMonths(m - 1).AddDays(d - 1).AddHours(h).AddMinutes(mi).AddSeconds(s);
        if (tz.IsInvalidTime(local)) local = local.AddHours(1);
        var utc = TimeZoneInfo.ConvertTimeToUtc(local, tz);
        return new DateTimeOffset(utc, TimeSpan.Zero).ToUnixTimeMilliseconds();
    }

    public static DateTime ToLocal(double ms) => DateTimeOffset.FromUnixTimeMilliseconds((long)ms).LocalDateTime;
    public static double FromLocal(DateTime t) => new DateTimeOffset(t).ToUnixTimeMilliseconds();
}

public readonly record struct Ymd(int Y, int M, int D, int H, int Mi, int Wd);
