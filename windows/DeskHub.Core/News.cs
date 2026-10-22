// 新闻和订阅：公开 RSS / Atom。和 Mac 版 News.swift、Feeds.swift 对应。
using System.Globalization;
using System.Text.RegularExpressions;

namespace DeskHub.Core;

public record NewsFeed(string Tag, string Url);
public record NewsSource(string Id, string Name, bool T2s, bool IsDefault, NewsFeed[] Feeds);

public static class News
{
    public static readonly NewsSource[] Sources =
    {
        new("rthk", "香港电台", true, true, new NewsFeed[] {
            new("财经", "http://rthk9.rthk.hk/rthk/news/rss/c_expressnews_cfinance.xml"),
            new("本地", "http://rthk9.rthk.hk/rthk/news/rss/c_expressnews_clocal.xml"),
            new("大中华", "http://rthk9.rthk.hk/rthk/news/rss/c_expressnews_greaterchina.xml"),
            new("国际", "http://rthk9.rthk.hk/rthk/news/rss/c_expressnews_cinternational.xml") }),
        new("bbc", "BBC 中文", false, true, new NewsFeed[] { new("国际", "https://feeds.bbci.co.uk/zhongwen/simp/rss.xml") }),
        new("wscn", "华尔街见闻", false, true, new NewsFeed[] { new("财经", "https://dedicated.wallstreetcn.com/rss.xml") }),
        new("chinanews", "中新网", false, true, new NewsFeed[] { new("大中华", "https://www.chinanews.com.cn/rss/scroll-news.xml") }),
        new("sspai", "少数派", false, true, new NewsFeed[] { new("科技", "https://sspai.com/feed") }),
        new("nytcn", "纽约时报中文网", false, false, new NewsFeed[] { new("国际", "https://cn.nytimes.com/rss/") }),
        new("cnbc", "CNBC（英文）", false, false, new NewsFeed[] { new("财经", "https://www.cnbc.com/id/10000664/device/rss/rss.html") }),
        new("bbcbiz", "BBC Business（英文）", false, false, new NewsFeed[] { new("财经", "https://feeds.bbci.co.uk/news/business/rss.xml") }),
        new("npr", "NPR（英文）", false, false, new NewsFeed[] { new("国际", "https://feeds.npr.org/1001/rss.xml") }),
        new("hn", "Hacker News（英文）", false, false, new NewsFeed[] { new("科技", "https://hnrss.org/frontpage") }),
    };

    public static List<string> DefaultIds => Sources.Where(s => s.IsDefault).Select(s => s.Id).ToList();
    public const int PerFeed = 14;

    public static List<NewsSource> Pick(IEnumerable<string>? enabled)
    {
        var ids = enabled?.ToList() ?? new List<string>();
        var picked = Sources.Where(s => ids.Contains(s.Id)).ToList();
        return picked.Count == 0 ? Sources.Where(s => s.IsDefault).ToList() : picked;
    }

    static string Tag(string xml, string tag)
    {
        var esc = Regex.Escape(tag);
        var m = xml.Match($"<{esc}[^>]*>([\\s\\S]*?)</{esc}>");
        return m == null ? "" : (m[1] ?? "").Rx("^<!\\[CDATA\\[([\\s\\S]*)\\]\\]>$", "$1").Trim();
    }

    public static string Decode(string s) =>
        s.Rx("<[^>]+>", "").Replace("&lt;", "<").Replace("&gt;", ">").Replace("&quot;", "\"").Replace("&#39;", "'").Replace("&nbsp;", " ").Replace("&amp;", "&");

    static readonly string[] Rfc822 = { "ddd, dd MMM yyyy HH:mm:ss zzz", "ddd, d MMM yyyy HH:mm:ss zzz", "dd MMM yyyy HH:mm:ss zzz", "ddd, dd MMM yyyy HH:mm zzz" };

    /** RSS 里的两种时间写法（RFC 822 的 pubDate、ISO 的 dc:date）→ 毫秒 */
    public static double? ParseDate(string s)
    {
        var t = s.Trim();
        if (t == "") return null;
        // +0800 → +08:00；GMT / UT / EST 之类换成偏移
        var u = t.Rx("\\s(GMT|UT|UTC|Z)$", " +00:00").Rx("\\sEST$", " -05:00").Rx("\\sEDT$", " -04:00").Rx("\\sPST$", " -08:00").Rx("\\sPDT$", " -07:00")
                 .Rx("\\s([+-]\\d{2})(\\d{2})$", " $1:$2");
        if (DateTimeOffset.TryParseExact(u, Rfc822, CultureInfo.InvariantCulture, DateTimeStyles.AllowWhiteSpaces, out var d)) return d.ToUnixTimeMilliseconds();
        if (t.Test("^\\d{4}-\\d{2}-\\d{2}T") && DateTimeOffset.TryParse(t, CultureInfo.InvariantCulture, DateTimeStyles.AssumeUniversal, out var iso)) return iso.ToUnixTimeMilliseconds();
        return null;
    }

    public static List<NewsItem> ParseRss(string xml, string tag, string source = "香港电台")
    {
        var items = new List<NewsItem>();
        foreach (var m in xml.MatchAll("<item[\\s>]([\\s\\S]*?)</item>"))
        {
            var it = m[1] ?? "";
            var title = Decode(Tag(it, "title"));
            var link0 = Decode(Tag(it, "link"));
            var link = link0 == "" ? Decode(Tag(it, "guid")) : link0;
            var date = Tag(it, "pubDate");
            if (title == "" || !link.Test("^https?://") || ParseDate(date == "" ? Tag(it, "dc:date") : date) is not double ts) continue;
            var desc = Decode(Tag(it, "description")).Rx("[編编]輯?[辑]?：[\\s\\S]*$", "").Rx("\\s+", " ").Trim().Head(120);
            items.Add(new NewsItem(title, link, ts, desc, tag, source));
        }
        return items;
    }

    public static List<NewsItem> ParseAtom(string xml, string tag, string source)
    {
        var o = new List<NewsItem>();
        foreach (var m in xml.MatchAll("<entry[\\s>]([\\s\\S]*?)</entry>"))
        {
            var it = m[1] ?? "";
            var title = Decode((it.Match("<title[^>]*>([\\s\\S]*?)</title>")?[1] ?? "").Rx("^<!\\[CDATA\\[([\\s\\S]*)\\]\\]>$", "$1")).Trim();
            var link = it.Match("<link[^>]*href=\"([^\"]+)\"")?[1] ?? "";
            var date = it.Match("<(?:updated|published)>([^<]+)</")?[1] ?? "";
            if (title == "" || !link.Test("^https?://") || ParseDate(date) is not double ts) continue;
            o.Add(new NewsItem(title, Decode(link), ts, "", tag, source));
        }
        return o;
    }

    /** 不管是 RSS 还是 Atom 都能读 */
    public static List<NewsItem> ParseFeed(string xml, string source)
    {
        var rss = ParseRss(xml, "", source);
        return rss.Count == 0 ? ParseAtom(xml, "", source) : rss;
    }

    public static string? FeedTitle(string xml) =>
        xml.Match("<title[^>]*>([\\s\\S]*?)</title>")?[1] is string t ? Decode(t.Rx("^<!\\[CDATA\\[([\\s\\S]*)\\]\\]>$", "$1")).Trim() : null;

    /** 合并排序：按时间倒序，财经稍微靠前；同一个链接只留一条 */
    public static List<NewsItem> Merge(IEnumerable<IEnumerable<NewsItem>> lists)
    {
        var seen = new HashSet<string>();
        static double Boost(NewsItem n) => n.Ts + (n.Tag == "财经" ? 2 * 3600e3 : 0);
        return lists.SelectMany(x => x).Where(n => seen.Add(n.Link)).Select((n, i) => (n, i))
            .OrderByDescending(x => Boost(x.n)).ThenBy(x => x.i).Select(x => x.n).ToList();
    }
}
