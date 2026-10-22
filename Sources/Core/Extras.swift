// 刘海条（歌词、内存）、桌面抽屉（文件归类）、K 线（日 K + 均线）的纯逻辑。
import Foundation

// —— 歌词：LRCLIB（免费、不用注册）的带时间轴歌词 ——
struct LrcLine: Equatable { let t: Double, text: String }

enum Lyrics {
  /** LRC 文本 → 按时间排好的行 */
  static func parse(_ lrc: String?) -> [LrcLine] {
    var out: [LrcLine] = []
    for raw in (lrc ?? "").components(separatedBy: "\n") {
      let stamps = raw.matchAll("\\[(\\d+):(\\d+(?:\\.\\d+)?)\\]")
      if stamps.isEmpty { continue }
      let text = raw.replace("\\[[^\\]]*\\]", "").trimmed()
      for m in stamps { out.append(LrcLine(t: Double(m[1]!)! * 60 + Double(m[2]!)!, text: text)) }
    }
    return out.sorted { $0.t < $1.t }
  }

  /** 当前进度对应的那一行（下标），还没到第一行返回 -1 */
  static func lineAt(_ lines: [LrcLine], _ pos: Double) -> Int {
    var lo = 0, hi = lines.count - 1, ans = -1
    while lo <= hi {
      let mid = (lo + hi) / 2
      if lines[mid].t <= pos { ans = mid; lo = mid + 1 } else { hi = mid - 1 }
    }
    return ans
  }

  /** 从候选里挑带时间轴、时长最接近（差 8 秒以内）的 */
  static func pickBest(_ list: [JSON], duration: Double) -> JSON? {
    list.filter { x in
      guard let s = x["syncedLyrics"] as? String, !s.isEmpty else { return false }
      let d = num(x["duration"]) ?? 0
      return duration == 0 || d == 0 || abs(d - duration) <= 8
    }.min { abs((num($0["duration"]) ?? 0) - duration) < abs((num($1["duration"]) ?? 0) - duration) }
  }

  /** osascript 读「音乐」的输出：状态␟歌名␟歌手␟专辑␟时长␟进度 */
  static func parseNowPlaying(_ out: String) -> (playing: Bool, title: String, artist: String, album: String, duration: Double, position: Double)? {
    let s = out.trimmed()
    if s.isEmpty || s == "stopped" { return nil }
    let f = s.components(separatedBy: "\u{1f}")
    guard f.count >= 6 else { return nil }
    let n = { (x: String) in Double(x.replacingOccurrences(of: ",", with: ".")) ?? 0 }
    return (f[0] == "playing", f[1], f[2], f[3], n(f[4]), n(f[5]))
  }

  static let script = """
  set US to (ASCII character 31)
  tell application "Music"
    if player state is not playing and player state is not paused then return "stopped"
    set t to current track
    return (player state as string) & US & (name of t) & US & (artist of t) & US & (album of t) & US & ((duration of t) as string) & US & ((player position) as string)
  end tell
  """
}

// —— 桌面抽屉：文件归类 ——
enum DeskFiles {
  static let kinds: [String: [String]] = [
    "doc": ["doc", "docx", "pages", "txt", "md", "rtf", "pdf", "xls", "xlsx", "numbers", "csv", "ppt", "pptx", "key"],
    "image": ["png", "jpg", "jpeg", "gif", "heic", "webp", "svg", "tiff", "psd"],
    "media": ["mp4", "mov", "mp3", "m4a", "wav", "aac"],
    "archive": ["zip", "rar", "7z", "dmg", "pkg", "tar", "gz"],
  ]

  /** folder / app / doc / image / media / archive / other */
  static func kindOf(_ name: String, isDir: Bool) -> String {
    if name.lowercased().hasSuffix(".app") { return "app" }
    if isDir { return "folder" }
    let ext = (name as NSString).pathExtension.lowercased()
    for (k, list) in kinds where list.contains(ext) { return k }
    return "other"
  }

  /** 目录项 → (显示名, 种类, 是否 iCloud 占位)。隐藏文件、Office 临时锁文件跳过 */
  static func item(_ name: String, isDir: Bool) -> (name: String, kind: String, cloud: Bool)? {
    if let m = name.match("^\\.(.+)\\.icloud$") { return (m[1]!, kindOf(m[1]!, isDir: false), true) }
    if name.hasPrefix(".") || name == "Icon\r" || name.hasPrefix("~$") { return nil }
    return (name, kindOf(name, isDir: isDir), false)
  }
}

// —— K 线 ——
struct KLine {
  var dates: [String] = []
  var open: [Double] = [], high: [Double] = [], low: [Double] = [], close: [Double] = []
  var ma10: [Double?] = [], ma20: [Double?] = []
  var isEmpty: Bool { close.isEmpty }

  /** 均线：前 p-1 天没有 */
  static func ma(_ close: [Double], _ p: Int) -> [Double?] {
    close.indices.map { i in i + 1 < p ? nil : round2(close[(i + 1 - p)...i].reduce(0, +) / Double(p), 3) }
  }

  /** 新浪日 K 接口的 JSON → K 线 */
  static func fromSina(_ rows: [JSON]) -> KLine {
    var k = KLine()
    for r in rows {
      guard let o = num(r["open"]), let h = num(r["high"]), let l = num(r["low"]), let c = num(r["close"]) else { continue }
      k.dates.append(r["day"] as? String ?? ""); k.open.append(o); k.high.append(h); k.low.append(l); k.close.append(c)
    }
    k.ma10 = ma(k.close, 10); k.ma20 = ma(k.close, 20)
    return k
  }

  /** 量化系统快照里自带的 K 线（{dates, open, high, low, close, ma10?, ma20?}） */
  static func fromQuant(_ j: JSON?) -> KLine? {
    guard let j else { return nil }
    let arr = { (k: String) in (j[k] as? [Any] ?? []).map { num($0) } }
    let c = arr("close").compactMap { $0 }
    guard !c.isEmpty else { return nil }
    var k = KLine()
    k.dates = j["dates"] as? [String] ?? []
    k.open = arr("open").map { $0 ?? 0 }; k.high = arr("high").map { $0 ?? 0 }; k.low = arr("low").map { $0 ?? 0 }; k.close = c
    k.ma10 = j["ma10"] != nil ? arr("ma10") : ma(c, 10)
    k.ma20 = j["ma20"] != nil ? arr("ma20") : ma(c, 20)
    return k
  }
}

// —— 刘海条的内存口径：活跃 + 联动 + 被压缩占用（接近「活动监视器」） ——
enum SysInfo {
  static func parseVmStat(_ text: String) -> Double {
    let page = Double(text.match("page size of (\\d+) bytes")?[1] ?? "") ?? 16384
    let get = { (k: String) in Double(text.match(k + ":\\s+(\\d+)")?[1] ?? "") ?? 0 }
    return (get("Pages active") + get("Pages wired down") + get("Pages occupied by compressor")) * page
  }
}
