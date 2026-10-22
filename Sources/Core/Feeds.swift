// 新组件的数据解析：加密货币（CoinGecko）、GitHub 仓库、倒数日、Atom 订阅。都是公开接口，不用注册。
import Foundation

struct CoinQuote: Equatable { var id: String, price: Double, change: Double? }

enum Crypto {
  /** 常见的简写 → CoinGecko 的 id */
  static let alias = ["btc": "bitcoin", "eth": "ethereum", "sol": "solana", "bnb": "binancecoin", "doge": "dogecoin", "xrp": "ripple",
                      "ada": "cardano", "ton": "the-open-network", "trx": "tron", "usdt": "tether", "比特币": "bitcoin", "以太坊": "ethereum"]
  static let symbol = ["bitcoin": "BTC", "ethereum": "ETH", "solana": "SOL", "binancecoin": "BNB", "dogecoin": "DOGE", "ripple": "XRP",
                       "cardano": "ADA", "the-open-network": "TON", "tron": "TRX", "tether": "USDT"]
  static func id(_ s: String) -> String { let t = s.trimmed().lowercased(); return alias[t] ?? t }
  static func url(_ ids: [String], vs: String) -> URL {
    URL(string: "https://api.coingecko.com/api/v3/simple/price?ids=\(ids.joined(separator: ","))&vs_currencies=\(vs)&include_24hr_change=true")!
  }
  static func parse(_ j: JSON, ids: [String], vs: String) -> [CoinQuote] {
    ids.compactMap { id in
      guard let o = j[id] as? JSON, let p = num(o[vs]) else { return nil }
      return CoinQuote(id: id, price: p, change: num(o["\(vs)_24h_change"]))
    }
  }
}

struct RepoInfo: Equatable { var name: String, stars: Int, forks: Int, issues: Int, downloads: Int? }

enum GitHubAPI {
  static func repoURL(_ r: String) -> URL? { URL(string: "https://api.github.com/repos/" + r.trimmed()) }
  static func releasesURL(_ r: String) -> URL? { URL(string: "https://api.github.com/repos/\(r.trimmed())/releases?per_page=100") }
  static func parseRepo(_ j: JSON) -> RepoInfo? {
    guard let name = j["full_name"] as? String else { return nil }
    return RepoInfo(name: name, stars: Int(num(j["stargazers_count"]) ?? 0), forks: Int(num(j["forks_count"]) ?? 0), issues: Int(num(j["open_issues_count"]) ?? 0), downloads: nil)
  }
  /** 所有版本、所有安装包的下载次数加起来（GitHub 自带的计数） */
  static func totalDownloads(_ releases: [JSON]) -> Int {
    releases.reduce(0) { sum, r in sum + (r["assets"] as? [JSON] ?? []).reduce(0) { $0 + Int(num($1["download_count"]) ?? 0) } }
  }
}

enum Countdown {
  /** 今天到那天还有几天（负数 = 已经过去几天）。date 写成 2026-12-25 */
  static func days(_ date: String, now: Double = nowMs()) -> Int? {
    let p = date.components(separatedBy: "-").compactMap { Int($0) }
    guard p.count == 3 else { return nil }
    let t = ymd(now)
    return Int(((localMs(p[0], p[1], p[2]) - localMs(t.y, t.m, t.d)) / 86400e3).rounded())
  }
}

extension News {
  /** Atom（很多博客、GitHub 用这种）：<entry><title/><link href=""/><updated/></entry> */
  static func parseAtom(_ xml: String, tag: String, source: String) -> [NewsItem] {
    xml.matchAll("<entry[\\s>]([\\s\\S]*?)</entry>").compactMap { m in
      let it = m[1] ?? ""
      let title = decode(it.match("<title[^>]*>([\\s\\S]*?)</title>")?[1]?.replace("^<!\\[CDATA\\[([\\s\\S]*)\\]\\]>$", "$1") ?? "").trimmed()
      let link = it.match("<link[^>]*href=\"([^\"]+)\"")?[1] ?? ""
      let date = it.match("<(?:updated|published)>([^<]+)</")?[1] ?? ""
      guard !title.isEmpty, link.test("^https?://"), let ts = parseDate(date) else { return nil }
      return NewsItem(title: title, link: decode(link), ts: ts, desc: "", tag: tag, source: source)
    }
  }

  /** 不管是 RSS 还是 Atom 都能读 */
  static func parseFeed(_ xml: String, source: String) -> [NewsItem] {
    let rss = parseRss(xml, tag: "", source: source)
    return rss.isEmpty ? parseAtom(xml, tag: "", source: source) : rss
  }

  /** 订阅源自己的名字（<channel><title> 或 Atom 的 <feed><title>） */
  static func feedTitle(_ xml: String) -> String? {
    xml.match("<title[^>]*>([\\s\\S]*?)</title>")?[1].map { decode($0.replace("^<!\\[CDATA\\[([\\s\\S]*)\\]\\]>$", "$1")).trimmed() }
  }
}
