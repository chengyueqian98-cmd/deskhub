// 新闻：多个公开 RSS 源。来源登记表、解析、合并从 Electron 版 newsSources.js / news.js 移植。
// 繁体来源（香港电台）用系统自带的 Hant-Hans 转换转成简体——原生版直接调 Foundation，不再起 osascript。
import Foundation

struct NewsFeed { let tag: String, url: String }
struct NewsSource { let id: String, name: String, t2s: Bool, isDefault: Bool, feeds: [NewsFeed] }

enum News {
  static let sources: [NewsSource] = [
    NewsSource(id: "rthk", name: "香港电台", t2s: true, isDefault: true, feeds: [
      NewsFeed(tag: "财经", url: "http://rthk9.rthk.hk/rthk/news/rss/c_expressnews_cfinance.xml"),
      NewsFeed(tag: "本地", url: "http://rthk9.rthk.hk/rthk/news/rss/c_expressnews_clocal.xml"),
      NewsFeed(tag: "大中华", url: "http://rthk9.rthk.hk/rthk/news/rss/c_expressnews_greaterchina.xml"),
      NewsFeed(tag: "国际", url: "http://rthk9.rthk.hk/rthk/news/rss/c_expressnews_cinternational.xml"),
    ]),
    NewsSource(id: "bbc", name: "BBC 中文", t2s: false, isDefault: true, feeds: [NewsFeed(tag: "国际", url: "https://feeds.bbci.co.uk/zhongwen/simp/rss.xml")]),
    NewsSource(id: "wscn", name: "华尔街见闻", t2s: false, isDefault: true, feeds: [NewsFeed(tag: "财经", url: "https://dedicated.wallstreetcn.com/rss.xml")]),
    NewsSource(id: "chinanews", name: "中新网", t2s: false, isDefault: true, feeds: [NewsFeed(tag: "大中华", url: "https://www.chinanews.com.cn/rss/scroll-news.xml")]),
    NewsSource(id: "sspai", name: "少数派", t2s: false, isDefault: true, feeds: [NewsFeed(tag: "科技", url: "https://sspai.com/feed")]),
    NewsSource(id: "nytcn", name: "纽约时报中文网", t2s: false, isDefault: false, feeds: [NewsFeed(tag: "国际", url: "https://cn.nytimes.com/rss/")]),
    NewsSource(id: "cnbc", name: "CNBC（英文）", t2s: false, isDefault: false, feeds: [NewsFeed(tag: "财经", url: "https://www.cnbc.com/id/10000664/device/rss/rss.html")]),
    NewsSource(id: "bbcbiz", name: "BBC Business（英文）", t2s: false, isDefault: false, feeds: [NewsFeed(tag: "财经", url: "https://feeds.bbci.co.uk/news/business/rss.xml")]),
    NewsSource(id: "npr", name: "NPR（英文）", t2s: false, isDefault: false, feeds: [NewsFeed(tag: "国际", url: "https://feeds.npr.org/1001/rss.xml")]),
    NewsSource(id: "hn", name: "Hacker News（英文）", t2s: false, isDefault: false, feeds: [NewsFeed(tag: "科技", url: "https://hnrss.org/frontpage")]),
  ]
  static var defaultIds: [String] { sources.filter(\.isDefault).map(\.id) }
  /** 每个源最多取这么多条：不然某一个源会把整页刷满 */
  static let perFeed = 14

  /** 要用的来源；不传或全都不认识就用默认的 */
  static func pick(_ enabled: [String]?) -> [NewsSource] {
    let ids = enabled ?? []
    let picked = sources.filter { ids.contains($0.id) }
    return picked.isEmpty ? sources.filter(\.isDefault) : picked
  }

  private static func pick(_ xml: String, _ tag: String) -> String {
    let esc = NSRegularExpression.escapedPattern(for: tag)
    guard let m = xml.match("<\(esc)[^>]*>([\\s\\S]*?)</\(esc)>") else { return "" }
    return (m[1] ?? "").replace("^<!\\[CDATA\\[([\\s\\S]*)\\]\\]>$", "$1").trimmed()
  }

  static func decode(_ s: String) -> String {
    s.replace("<[^>]+>", "")
      .replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">")
      .replacingOccurrences(of: "&quot;", with: "\"").replacingOccurrences(of: "&#39;", with: "'")
      .replacingOccurrences(of: "&nbsp;", with: " ").replacingOccurrences(of: "&amp;", with: "&")
  }

  private static let rfc822: [DateFormatter] = ["EEE, dd MMM yyyy HH:mm:ss Z", "EEE, d MMM yyyy HH:mm:ss Z", "EEE, dd MMM yyyy HH:mm:ss zzz", "dd MMM yyyy HH:mm:ss Z", "EEE, dd MMM yyyy HH:mm Z"].map {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = $0
    return f
  }
  private static let iso: [ISO8601DateFormatter] = {
    let a = ISO8601DateFormatter()
    let b = ISO8601DateFormatter(); b.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return [a, b]
  }()

  /** RSS 里的两种时间写法（RFC 822 的 pubDate、ISO 的 dc:date）→ 毫秒 */
  static func parseDate(_ s: String) -> Double? {
    let t = s.trimmed()
    if t.isEmpty { return nil }
    for f in rfc822 { if let d = f.date(from: t) { return d.timeIntervalSince1970 * 1000 } }
    for f in iso { if let d = f.date(from: t) { return d.timeIntervalSince1970 * 1000 } }
    return nil
  }

  /** RSS 文本 → 新闻条目 */
  static func parseRss(_ xml: String, tag: String, source: String = "香港电台") -> [NewsItem] {
    var items: [NewsItem] = []
    for m in xml.matchAll("<item[\\s>]([\\s\\S]*?)</item>") {
      let it = m[1] ?? ""
      let title = decode(pick(it, "title"))
      let link0 = decode(pick(it, "link"))
      let link = link0.isEmpty ? decode(pick(it, "guid")) : link0
      let date = pick(it, "pubDate")
      guard !title.isEmpty, link.test("^https?://"), let ts = parseDate(date.isEmpty ? pick(it, "dc:date") : date) else { continue }
      let desc = decode(pick(it, "description"))
        .replace("[編编]輯?[辑]?：[\\s\\S]*$", "")
        .replace("\\s+", " ").trimmed().head(120)
      items.append(NewsItem(title: title, link: link, ts: ts, desc: desc, tag: tag, source: source))
    }
    return items
  }

  /** 合并排序：按时间倒序，财经稍微靠前（相当于晚 2 小时也排在一起）；同一个链接只留一条 */
  static func merge(_ lists: [[NewsItem]]) -> [NewsItem] {
    var seen = Set<String>()
    let boost = { (n: NewsItem) in n.ts + (n.tag == "财经" ? 2 * 3600e3 : 0) }
    return lists.flatMap { $0 }
      .filter { seen.insert($0.link).inserted }
      .enumerated().sorted { boost($0.element) != boost($1.element) ? boost($0.element) > boost($1.element) : $0.offset < $1.offset }
      .map(\.element)
  }

  /** 繁体 → 简体（系统自带的转换） */
  static func t2s(_ s: String) -> String {
    s.applyingTransform(StringTransform("Hant-Hans"), reverse: false) ?? s
  }
}
