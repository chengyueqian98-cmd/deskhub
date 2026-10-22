// 小工具：JSON 取值、JS 风格的数字转文字、正则。Core 里只用 Foundation，测试不需要窗口。
import Foundation

typealias JSON = [String: Any]

/** 任何来源的数字（JSON 里的 NSNumber、字符串）→ Double；不是有限数就是 nil。布尔值不算数字 */
func num(_ v: Any?) -> Double? {
  switch v {
  case let n as NSNumber:
    if CFGetTypeID(n) == CFBooleanGetTypeID() { return nil }
    let d = n.doubleValue
    return d.isFinite ? d : nil
  case let s as String:
    guard let d = Double(s.trimmingCharacters(in: .whitespaces)) else { return nil }
    return d.isFinite ? d : nil
  default:
    return nil
  }
}

func str(_ v: Any?) -> String? { v as? String }

/** 和 JS 的 String(number) 一样：整数不带 .0，小数用最短表示（14.5、0.30000000000000004） */
func jsNum(_ d: Double) -> String {
  if d == d.rounded(), abs(d) < 1e15 { return String(Int64(d)) }
  return "\(d)"
}

/** JS 的 (x).toFixed(n) 再转回数字 */
func round2(_ x: Double, _ digits: Int = 2) -> Double {
  let p = pow(10.0, Double(digits))
  return (x * p).rounded() / p
}

func nowMs() -> Double { Date().timeIntervalSince1970 * 1000 }

func pad2(_ n: Int) -> String { n < 10 ? "0\(n)" : "\(n)" }

// —— 正则 ——
private var regexCache: [String: NSRegularExpression] = [:]
private let regexLock = NSLock()

func regex(_ pattern: String, _ options: NSRegularExpression.Options = []) -> NSRegularExpression {
  let key = "\(options.rawValue)|\(pattern)"
  regexLock.lock(); defer { regexLock.unlock() }
  if let r = regexCache[key] { return r }
  let r = try! NSRegularExpression(pattern: pattern, options: options)
  regexCache[key] = r
  return r
}

extension String {
  var ns: NSString { self as NSString }
  var full: NSRange { NSRange(location: 0, length: ns.length) }

  func test(_ pattern: String, _ options: NSRegularExpression.Options = []) -> Bool {
    regex(pattern, options).firstMatch(in: self, range: full) != nil
  }

  /** 第一个匹配的各个分组（0 = 整段）；没匹配返回 nil */
  func match(_ pattern: String, _ options: NSRegularExpression.Options = []) -> [String?]? {
    guard let m = regex(pattern, options).firstMatch(in: self, range: full) else { return nil }
    return (0..<m.numberOfRanges).map { i in
      let r = m.range(at: i)
      return r.location == NSNotFound ? nil : ns.substring(with: r)
    }
  }

  func matchAll(_ pattern: String, _ options: NSRegularExpression.Options = []) -> [[String?]] {
    regex(pattern, options).matches(in: self, range: full).map { m in
      (0..<m.numberOfRanges).map { i in
        let r = m.range(at: i)
        return r.location == NSNotFound ? nil : ns.substring(with: r)
      }
    }
  }

  func replace(_ pattern: String, _ template: String, _ options: NSRegularExpression.Options = []) -> String {
    regex(pattern, options).stringByReplacingMatches(in: self, range: full, withTemplate: template)
  }

  func trimmed() -> String { trimmingCharacters(in: .whitespacesAndNewlines) }

  /** JS 的 slice(0, n)（按字符算） */
  func head(_ n: Int) -> String { String(prefix(n)) }
}

/** 本地时间的年月日时分 */
struct YMD { let y: Int, m: Int, d: Int, h: Int, mi: Int, wd: Int }   // m 从 1 开始；wd 0 = 周日
func ymd(_ ms: Double, _ tz: TimeZone = .current) -> YMD {
  var cal = Calendar(identifier: .gregorian)
  cal.timeZone = tz
  let c = cal.dateComponents([.year, .month, .day, .hour, .minute, .weekday], from: Date(timeIntervalSince1970: ms / 1000))
  return YMD(y: c.year!, m: c.month!, d: c.day!, h: c.hour!, mi: c.minute!, wd: c.weekday! - 1)
}

/** 本地时间 → 毫秒（月份从 1 开始，日可以越界，像 JS 的 new Date(y, m, d) 那样自动进位） */
func localMs(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ mi: Int = 0, _ s: Int = 0) -> Double {
  var cal = Calendar(identifier: .gregorian)
  cal.timeZone = .current
  var c = DateComponents()
  c.year = y; c.month = m; c.day = d; c.hour = h; c.minute = mi; c.second = s
  return cal.date(from: c)!.timeIntervalSince1970 * 1000
}
