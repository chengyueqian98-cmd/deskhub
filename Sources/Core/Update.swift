// 检查更新：问 GitHub「最新发布的版本是几号」，比现在装的新就提示一下（不自动下载、不自动安装）。
// 只发一个不带任何个人信息的请求（GitHub 公开接口），一天最多查一次。
import Foundation

enum Update {
  static let repo = "chengyueqian98-cmd/glancedesk"
  static var latestURL: URL { URL(string: "https://api.github.com/repos/\(repo)/releases/latest")! }
  static var releasesPage: String { "https://github.com/\(repo)/releases/latest" }

  /** 版本号比大小：0.4.10 > 0.4.9；前面的 v 和后面的 -beta 之类忽略。返回 -1 / 0 / 1 */
  static func compare(_ a: String, _ b: String) -> Int {
    func parts(_ s: String) -> [Int] {
      s.trimmed().replace("^[vV]", "").components(separatedBy: CharacterSet(charactersIn: "-+ ")).first!
        .components(separatedBy: ".").map { Int($0) ?? 0 }
    }
    let x = parts(a), y = parts(b)
    for i in 0..<max(x.count, y.count) {
      let p = i < x.count ? x[i] : 0, q = i < y.count ? y[i] : 0
      if p != q { return p < q ? -1 : 1 }
    }
    return 0
  }

  struct Release: Equatable { let version: String, page: String, notes: String }

  /** GitHub releases/latest 的 JSON → 版本号、发布页、更新说明（草稿和预发布不算） */
  static func parse(_ j: JSON) -> Release? {
    guard let tag = j["tag_name"] as? String, (j["draft"] as? Bool) != true, (j["prerelease"] as? Bool) != true else { return nil }
    return Release(version: tag.replace("^[vV]", ""), page: j["html_url"] as? String ?? releasesPage, notes: String((j["body"] as? String ?? "").prefix(600)))
  }

  /** 有没有比当前版本新的（用户点过「跳过这个版本」的不算） */
  static func newer(_ r: Release?, than current: String, skip: String?) -> Release? {
    guard let r, compare(r.version, current) > 0, r.version != skip else { return nil }
    return r
  }
}
