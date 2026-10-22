// 天气、加密货币、GitHub、倒数日、汇率、检查更新、邮箱服务商：都是公开接口的纯解析部分（请求在 App 里）。
using System.Text.Json.Nodes;
using static DeskHub.Core.I18n;

namespace DeskHub.Core;

// —— 天气：Open-Meteo（免费、不用注册和 Key） ——
public static class WeatherApi
{
    public static readonly (string name, double lat, double lon) DefaultCity = ("上海", 31.2304, 121.4737);

    /** WMO 天气代码 → 中文 + 图标名 */
    public static (string text, string icon) Describe(int c, int isDay = 1)
    {
        if (c == 0) return ("晴", isDay != 0 ? "sun" : "moon");
        if (c <= 2) return (c == 1 ? "晴间多云" : "多云", isDay != 0 ? "sun-cloud" : "moon-cloud");
        if (c == 3) return ("阴", "cloud");
        if (c == 45 || c == 48) return ("雾", "fog");
        if (c >= 51 && c <= 57) return ("毛毛雨", "rain");
        if (c >= 61 && c <= 67) return (c >= 65 ? "大雨" : c >= 63 ? "中雨" : "小雨", "rain");
        if (c >= 71 && c <= 77) return (c >= 75 ? "大雪" : "小雪", "snow");
        if (c >= 80 && c <= 82) return ("阵雨", "rain");
        if (c == 85 || c == 86) return ("阵雪", "snow");
        if (c >= 95) return ("雷雨", "storm");
        return ("—", "cloud");
    }

    public static string Url(double lat, double lon) =>
        $"https://api.open-meteo.com/v1/forecast?latitude={U.JsNum(lat)}&longitude={U.JsNum(lon)}&timezone=auto&forecast_days=5" +
        "&current=temperature_2m,apparent_temperature,relative_humidity_2m,weather_code,is_day,wind_speed_10m" +
        "&daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max";

    public static string SearchUrl(string q, string lang) =>
        $"https://geocoding-api.open-meteo.com/v1/search?name={Uri.EscapeDataString(q)}&count=8&language={lang}&format=json";

    public static List<(string name, double lat, double lon, string region)> ParseSearch(JsonNode? j)
    {
        var o = new List<(string, double, double, string)>();
        foreach (var r in j?["results"] as JsonArray ?? new JsonArray())
        {
            if (U.Str(r?["name"]) is not string n || U.Num(r?["latitude"]) is not double lat || U.Num(r?["longitude"]) is not double lon) continue;
            var region = string.Join(" · ", new[] { U.Str(r?["admin1"]), U.Str(r?["country"]) }.Where(x => !string.IsNullOrEmpty(x)));
            o.Add((n, lat, lon, region));
        }
        return o;
    }

    public static Weather? Parse(JsonNode? d, string city, double? now = null)
    {
        if (d?["current"] is not JsonObject c || d["daily"] is not JsonObject daily) return null;
        static int R(JsonNode? v) => (int)Math.Round(U.Num(v) ?? 0, MidpointRounding.AwayFromZero);
        var cur = Describe(R(c["weather_code"]), R(c["is_day"]));
        var times = U.Strs(daily["time"]);
        JsonNode? Col(string k, int i) => daily[k] is JsonArray a && i < a.Count ? a[i] : null;
        var days = times.Select((t, i) =>
        {
            var dd = Describe(R(Col("weather_code", i)));
            var rain = U.Num(Col("precipitation_probability_max", i));
            return new WxDay(t, R(Col("temperature_2m_max", i)), R(Col("temperature_2m_min", i)), rain == null ? null : (int)rain.Value, dd.text, dd.icon);
        }).ToList();
        return new Weather(city, now ?? U.NowMs(),
            new WxNow(R(c["temperature_2m"]), R(c["apparent_temperature"]), R(c["relative_humidity_2m"]), R(c["wind_speed_10m"]), cur.text, cur.icon), days);
    }
}

// —— 加密货币（CoinGecko 公开接口） ——
public static class Crypto
{
    public static readonly Dictionary<string, string> Alias = new()
    {
        ["btc"] = "bitcoin", ["eth"] = "ethereum", ["sol"] = "solana", ["bnb"] = "binancecoin", ["doge"] = "dogecoin", ["xrp"] = "ripple",
        ["ada"] = "cardano", ["ton"] = "the-open-network", ["trx"] = "tron", ["usdt"] = "tether", ["比特币"] = "bitcoin", ["以太坊"] = "ethereum",
    };
    public static readonly Dictionary<string, string> Symbol = new()
    {
        ["bitcoin"] = "BTC", ["ethereum"] = "ETH", ["solana"] = "SOL", ["binancecoin"] = "BNB", ["dogecoin"] = "DOGE", ["ripple"] = "XRP",
        ["cardano"] = "ADA", ["the-open-network"] = "TON", ["tron"] = "TRX", ["tether"] = "USDT",
    };
    public static string Id(string s) { var t = s.Trim().ToLowerInvariant(); return Alias.TryGetValue(t, out var a) ? a : t; }
    public static string Url(IEnumerable<string> ids, string vs) =>
        $"https://api.coingecko.com/api/v3/simple/price?ids={string.Join(",", ids)}&vs_currencies={vs}&include_24hr_change=true";
    public static List<CoinQuote> Parse(JsonNode? j, IEnumerable<string> ids, string vs) =>
        ids.Select(id => j?[id] is JsonObject o && U.Num(o[vs]) is double p ? new CoinQuote(id, p, U.Num(o[vs + "_24h_change"])) : null)
           .Where(x => x != null).Select(x => x!).ToList();
}

public static class GitHubApi
{
    public static string RepoUrl(string r) => "https://api.github.com/repos/" + r.Trim();
    public static string ReleasesUrl(string r) => $"https://api.github.com/repos/{r.Trim()}/releases?per_page=100";
    public static RepoInfo? ParseRepo(JsonNode? j) =>
        U.Str(j?["full_name"]) is string n ? new RepoInfo(n, (int)(U.Num(j!["stargazers_count"]) ?? 0), (int)(U.Num(j["forks_count"]) ?? 0), (int)(U.Num(j["open_issues_count"]) ?? 0), null) : null;
    public static int TotalDownloads(JsonNode? releases) =>
        (releases as JsonArray ?? new JsonArray()).Sum(r => (r?["assets"] as JsonArray ?? new JsonArray()).Sum(a => (int)(U.Num(a?["download_count"]) ?? 0)));
}

public static class Countdown
{
    /** 今天到那天还有几天（负数 = 已经过去几天）。date 写成 2026-12-25 */
    public static int? Days(string date, double? now = null)
    {
        var p = date.Split('-').Select(x => int.TryParse(x, out var n) ? n : (int?)null).ToList();
        if (p.Count != 3 || p.Any(x => x == null)) return null;
        var t = U.Ymd(now ?? U.NowMs());
        return (int)Math.Round((U.LocalMs(p[0]!.Value, p[1]!.Value, p[2]!.Value) - U.LocalMs(t.Y, t.M, t.D)) / 86400e3);
    }
}

// —— 汇率（open.er-api.com，免费、每天更新） ——
public static class FX
{
    public static string Url(string b) => $"https://open.er-api.com/v6/latest/{b.ToUpperInvariant()}";
    public static (Dictionary<string, double> rates, double updated)? Parse(JsonNode? j)
    {
        if (U.Str(j?["result"]) != "success" || j!["rates"] is not JsonObject r) return null;
        var rates = new Dictionary<string, double>();
        foreach (var (k, v) in r) if (U.Num(v) is double n) rates[k] = n;
        return (rates, (U.Num(j["time_last_update_unix"]) ?? 0) * 1000);
    }
    public static readonly Dictionary<string, string> Names = new()
    {
        ["USD"] = "美元", ["CNY"] = "人民币", ["HKD"] = "港币", ["EUR"] = "欧元", ["GBP"] = "英镑", ["JPY"] = "日元", ["KRW"] = "韩元",
        ["CAD"] = "加元", ["AUD"] = "澳元", ["SGD"] = "新加坡元", ["TWD"] = "新台币", ["CHF"] = "瑞士法郎",
    };
}

// —— 检查更新：只问 GitHub 最新版本号，不自动下载安装 ——
public static class Update
{
    public const string Repo = "chengyueqian98-cmd/deskhub";
    public static string LatestUrl => $"https://api.github.com/repos/{Repo}/releases/latest";
    public static string ReleasesPage => $"https://github.com/{Repo}/releases/latest";

    public static int Compare(string a, string b)
    {
        static int[] Parts(string s) => s.Trim().Rx("^[vV]", "").Split('-', '+', ' ')[0].Split('.').Select(x => int.TryParse(x, out var n) ? n : 0).ToArray();
        var x = Parts(a); var y = Parts(b);
        for (int i = 0; i < Math.Max(x.Length, y.Length); i++)
        {
            int p = i < x.Length ? x[i] : 0, q = i < y.Length ? y[i] : 0;
            if (p != q) return p < q ? -1 : 1;
        }
        return 0;
    }

    public record Release(string Version, string Page, string Notes);

    public static Release? Parse(JsonNode? j)
    {
        if (U.Str(j?["tag_name"]) is not string tag || U.Bool(j!["draft"]) == true || U.Bool(j["prerelease"]) == true) return null;
        return new Release(tag.Rx("^[vV]", ""), U.Str(j["html_url"]) ?? ReleasesPage, (U.Str(j["body"]) ?? "").Head(600));
    }

    public static Release? Newer(Release? r, string current, string? skip) =>
        r != null && Compare(r.Version, current) > 0 && r.Version != skip ? r : null;
}

// —— 邮箱服务商（IMAP，只读；密码是应用专用密码） ——
public record MailProvider(string Id, string Name, string Host, int Port, string Help, string Web);

public static class MailProviders
{
    public static readonly MailProvider[] All =
    {
        new("gmail", "Gmail", "imap.gmail.com", 993, "https://myaccount.google.com/apppasswords", "https://mail.google.com/mail/u/0/#search/rfc822msgid%3A"),
        new("outlook", "Outlook / Hotmail", "outlook.office365.com", 993, "https://account.live.com/proofs/AppPassword", "https://outlook.live.com/mail/"),
        new("icloud", "iCloud", "imap.mail.me.com", 993, "https://account.apple.com/account/manage", "https://www.icloud.com/mail"),
        new("qq", "QQ 邮箱", "imap.qq.com", 993, "https://wx.mail.qq.com/", "https://wx.mail.qq.com/"),
        new("163", "网易 163", "imap.163.com", 993, "https://mail.163.com/", "https://mail.163.com/"),
        new("yahoo", "Yahoo", "imap.mail.yahoo.com", 993, "https://login.yahoo.com/account/security", "https://mail.yahoo.com/"),
        new("custom", "其他", "", 993, "", ""),
    };
    public static MailProvider By(string? id) => All.FirstOrDefault(p => p.Id == id) ?? All[0];

    public static string Guess(string email)
    {
        var d = email.ToLowerInvariant().Split('@').Last();
        if (d.Contains("gmail") || d.Contains("googlemail")) return "gmail";
        if (d.Contains("icloud") || d.Contains("me.com") || d.Contains("mac.com")) return "icloud";
        if (d.Contains("outlook") || d.Contains("hotmail") || d.Contains("live.")) return "outlook";
        if (d.Contains("qq.com") || d.Contains("foxmail")) return "qq";
        if (d.Contains("163.com") || d.Contains("126.com")) return "163";
        if (d.Contains("yahoo")) return "yahoo";
        return "custom";
    }

    /** 在网页里打开这封（Gmail 能直接定位到这封，其它邮箱打开收件箱） */
    public static string WebUrl(MailProvider p, string msgid) =>
        p.Id == "gmail" && msgid != "" ? p.Web + Uri.EscapeDataString(msgid) : p.Web;

    /** "张三 <a@b.com>" → (张三, a@b.com) */
    public static (string name, string email) ParseSender(string s)
    {
        var m = s.Match("^\\s*\"?([^\"<]*?)\"?\\s*<([^>]+)>\\s*$");
        if (m != null) { var n = (m[1] ?? "").Trim(); return (n == "" ? m[2]! : n, m[2]!); }
        return (s.Trim(), s.Trim());
    }

    public static string NoSubject => L("（无主题）");
}
