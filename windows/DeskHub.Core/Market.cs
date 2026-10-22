// 行情：新浪公开接口（免费、延迟数据）。只做展示和提醒，不做买卖、不给建议。和 Mac 版 Market.swift 对应。
using System.Globalization;
using System.Text.RegularExpressions;
using static DeskHub.Core.I18n;

namespace DeskHub.Core;

public static class Market
{
    public static readonly Dictionary<string, string> Aliases = new()
    {
        ["上证指数"] = "sh000001", ["上证"] = "sh000001", ["深证成指"] = "sz399001", ["深证"] = "sz399001", ["创业板指"] = "sz399006", ["创业板"] = "sz399006",
        ["沪深300"] = "sh000300", ["科创50"] = "sh000688", ["恒生指数"] = "rt_hkHSI", ["恒指"] = "rt_hkHSI", ["恒生科技"] = "rt_hkHSTECH",
        ["标普500"] = "gb_inx", ["标普"] = "gb_inx", ["纳斯达克"] = "gb_ixic", ["纳指"] = "gb_ixic", ["道琼斯"] = "gb_dji", ["道指"] = "gb_dji",
    };

    public static readonly string[] DefaultWatch = { "sh000001", "sz399001", "rt_hkHSI", "gb_ixic", "gb_inx", "rt_hk00700", "gb_aapl", "gb_nvda" };

    /** 用户输入（代码、别名）→ 新浪代码；认不出返回 null */
    public static string? ToSinaKey(string input)
    {
        var s = input.Trim();
        if (s == "") return null;
        if (Aliases.TryGetValue(s, out var a)) return a;
        if (s.Test("^(sh|sz|bj)\\d{6}$", RegexOptions.IgnoreCase)) return s.ToLowerInvariant();
        if (s.Test("^rt_hk[0-9A-Z]+$") || s.Test("^gb_[a-z$.]+$")) return s;
        if (s.Test("^\\d{6}$"))
        {
            var c = s[0];
            if ("695".Contains(c)) return "sh" + s;
            if ("0312".Contains(c)) return "sz" + s;
            if ("48".Contains(c)) return "bj" + s;
            return null;
        }
        static string Hk(string digits) => "rt_hk" + new string('0', Math.Max(0, 5 - digits.Length)) + digits;
        if (s.Test("^\\d{1,5}$")) return Hk(s);
        if (s.Test("^(hk)?\\d{1,5}(\\.hk)?$", RegexOptions.IgnoreCase)) return Hk(s.Rx("\\D", ""));
        if (s.Test("^[A-Za-z][A-Za-z.]{0,9}$"))
        {
            var low = s.ToLowerInvariant();
            int i = low.IndexOf('.');
            if (i >= 0) low = low[..i] + "$" + low[(i + 1)..];
            return "gb_" + low;
        }
        return null;
    }

    public static string MarketOf(string key) => key.Test("^(sh|sz|bj)") ? "cn" : key.StartsWith("rt_hk") ? "hk" : "us";

    public static string DisplayCode(string key)
    {
        if (key.Test("^(sh|sz|bj)")) return key[2..];
        if (key.StartsWith("rt_hk")) return key[5..];
        return key.Length > 3 ? key[3..].Replace("$", ".").ToUpperInvariant() : key;
    }

    public static bool IsIndex(string key) => key.Test("^sh000|^sz399|^rt_hk[A-Z]|^gb_(inx|ixic|dji)$");

    static double? N(string? x)
    {
        if (x == null) return null;
        var m = x.Trim().Match("^[-+]?(\\d+\\.?\\d*|\\.\\d+)([eE][-+]?\\d+)?");
        return m == null ? null : double.Parse(m[0]!, CultureInfo.InvariantCulture);
    }

    /** 北京时间字符串 → 毫秒 */
    public static double? BjToMs(string? date, string? time = "00:00")
    {
        var m = (date ?? "").Match("(\\d{4})[/-](\\d{2})[/-](\\d{2})");
        var t = (time ?? "").Match("(\\d{2}):(\\d{2})(?::(\\d{2}))?");
        if (m == null || t == null) return null;
        var utc = new DateTime(int.Parse(m[1]!), int.Parse(m[2]!), int.Parse(m[3]!), 0, 0, 0, DateTimeKind.Utc)
            .AddHours(int.Parse(t[1]!) - 8).AddMinutes(int.Parse(t[2]!)).AddSeconds(int.Parse(t[3] ?? "0"));
        return new DateTimeOffset(utc).ToUnixTimeMilliseconds();
    }

    public class ParseError : Exception { public ParseError(string m) : base(m) { } }

    /** 解析新浪一条返回（逗号分隔的字段），各市场字段位置不同 */
    public static Quote ParseQuote(string key, string raw)
    {
        var f = raw.Split(',');
        string? At(int i) => i < f.Length ? f[i] : null;
        var mk = MarketOf(key);
        var q = new Quote { Key = key, Code = DisplayCode(key), Market = mk, Index = IsIndex(key) };
        if (mk == "cn")
        {
            q.Name = At(0) ?? "";
            q.Prev = N(At(2)); q.Price = N(At(3));
            if (q.Price == null || q.Price == 0) q.Price = q.Prev;
            q.Open = N(At(1)); q.High = N(At(4)); q.Low = N(At(5));
            q.Ts = BjToMs(At(30), At(31));
        }
        else if (mk == "hk")
        {
            q.Name = string.IsNullOrEmpty(At(1)) ? At(0) ?? "" : At(1)!;
            q.Price = N(At(6)); q.Prev = N(At(3)); q.Open = N(At(2)); q.High = N(At(4)); q.Low = N(At(5));
            q.Ts = BjToMs(At(17), At(18));
        }
        else
        {
            q.Name = At(0) ?? "";
            double? price = N(At(1)), chg = N(At(4));
            q.Price = price;
            q.Prev = price != null && chg != null ? U.Round2(price.Value - chg.Value, 4) : null;
            q.Open = N(At(5)); q.High = N(At(6)); q.Low = N(At(7));
            var dt = (At(3) ?? "").Split(' ');
            q.Ts = BjToMs(dt[0], dt.Length > 1 ? dt[1] : "00:00");
        }
        if (q.Price is not double p || p <= 0 || q.Name == "") throw new ParseError("返回数据不完整");
        if (q.Prev is double prev && prev != 0)
        {
            q.Chg = U.Round2(p - prev, 4);
            q.Pct = U.Round2((p - prev) / prev * 100);
        }
        if (q.Pct is double pct && Math.Abs(pct) > 50) throw new ParseError("涨跌幅异常");
        return q;
    }

    public static Dictionary<string, string> SplitResponse(string text)
    {
        var o = new Dictionary<string, string>();
        foreach (var m in text.MatchAll("hq_str_([\\w$]+)=\"([^\"]*)\"")) o[m[1]!] = m[2] ?? "";
        return o;
    }

    static readonly Dictionary<string, (string tz, (int, int)[] ranges)> Sessions = new()
    {
        ["cn"] = ("Asia/Shanghai", new[] { (570, 690), (780, 900) }),
        ["hk"] = ("Asia/Hong_Kong", new[] { (570, 720), (780, 960) }),
        ["us"] = ("America/New_York", new[] { (570, 960) }),
    };

    public static bool IsOpen(string market, double? ms = null)
    {
        if (!Sessions.TryGetValue(market, out var s)) return false;
        var t = U.Ymd(ms ?? U.NowMs(), U.Zone(s.tz));
        if (t.Wd == 0 || t.Wd == 6) return false;
        int mins = t.H * 60 + t.Mi;
        return s.ranges.Any(r => mins >= r.Item1 && mins < r.Item2);
    }

    /** live 交易中 / closed 已收盘 / stale 数据过期 / fail 获取失败 */
    public static string QuoteStatus(Quote? q, double? ms = null)
    {
        var now = ms ?? U.NowMs();
        if (q == null || q.Failed) return "fail";
        if (!IsOpen(q.Market, now)) return "closed";
        if (q.Ts is double ts && now - ts > 30 * 60 * 1000) return "stale";
        return "live";
    }

    /** 涨跌提醒：涨跌幅超过阈值时提醒，每只每天只提醒一次 */
    public static List<(string title, string body)> CheckAlerts(IEnumerable<Quote> quotes, double pct, HashSet<string> memo, string day)
    {
        var o = new List<(string, string)>();
        foreach (var q in quotes)
        {
            if (q.Failed || q.Pct is not double p || q.Price is not double price) continue;
            if (pct <= 0 || Math.Abs(p) < pct) continue;
            var k = $"{day}|{q.Key}|pct{(p > 0 ? "+" : "-")}";
            if (!memo.Add(k)) continue;
            var name = $"{q.Name}（{q.Code}）";
            o.Add((L(p > 0 ? "%@ 涨幅 %@%%" : "%@ 跌幅 %@%%", name, Math.Abs(p).ToString("0.00", CultureInfo.InvariantCulture)),
                   L("现价 %@，超过你设的 %@%% 提醒线", U.JsNum(price), U.JsNum(pct))));
        }
        return o;
    }
}
