// 邮件格式解析（IMAP 读到的原始邮件 → 发件人、主题、时间、正文）。纯函数，Windows 版的 C# 也按这份逻辑写。
//   · 头部的编码词：=?UTF-8?B?…?= / =?GBK?Q?…?=
//   · 正文：multipart 递归找 text/plain（没有就把 text/html 去标签），base64 / quoted-printable，各种字符集
import Foundation

enum Mime {
  /** 字符集名字 → Foundation 的编码（中文邮件常见 GBK / GB2312 / GB18030，一律按 GB18030 解） */
  static func encoding(_ charset: String) -> String.Encoding {
    switch charset.lowercased().replacingOccurrences(of: "\"", with: "") {
    case "gbk", "gb2312", "gb18030", "x-gbk", "cp936":
      return String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
    case "big5": return String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.big5.rawValue)))
    case "iso-8859-1", "latin1", "us-ascii", "ascii": return .isoLatin1
    case "windows-1252", "cp1252": return .windowsCP1252
    case "shift_jis", "shift-jis": return .shiftJIS
    default: return .utf8
    }
  }

  static func decode(_ data: Data, charset: String) -> String {
    String(data: data, encoding: encoding(charset)) ?? String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
  }

  /** quoted-printable → 字节（=E4=BD=A0 → 你；行尾的 = 是软换行） */
  static func qp(_ s: String, header: Bool = false) -> Data {
    var out = Data()
    let b = Array(s.utf8)
    var i = 0
    while i < b.count {
      let c = b[i]
      if c == UInt8(ascii: "=") {
        if i + 2 < b.count, let v = UInt8(String(bytes: b[(i + 1)...(i + 2)], encoding: .ascii) ?? "", radix: 16) { out.append(v); i += 3; continue }
        // 软换行：=\r\n 或 =\n
        if i + 1 < b.count && b[i + 1] == 10 { i += 2; continue }
        if i + 2 < b.count && b[i + 1] == 13 && b[i + 2] == 10 { i += 3; continue }
        out.append(c); i += 1; continue
      }
      out.append(header && c == UInt8(ascii: "_") ? 32 : c)
      i += 1
    }
    return out
  }

  /** 头部的编码词：=?charset?B|Q?text?=，相邻两个编码词之间的空白要去掉 */
  static func decodeHeader(_ s: String) -> String {
    let re = regex("=\\?([^?]+)\\?([BbQq])\\?([^?]*)\\?=")
    let ns = s as NSString
    var out = ""
    var last = 0
    var prevWasWord = false
    for m in re.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
      let gap = ns.substring(with: NSRange(location: last, length: m.range.location - last))
      if !(prevWasWord && gap.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) { out += gap }
      let charset = ns.substring(with: m.range(at: 1)).components(separatedBy: "*")[0]
      let enc = ns.substring(with: m.range(at: 2)).uppercased(), text = ns.substring(with: m.range(at: 3))
      let data: Data? = enc == "B" ? Data(base64Encoded: text.padding(toLength: (text.count + 3) / 4 * 4, withPad: "=", startingAt: 0)) : qp(text, header: true)
      out += data.map { decode($0, charset: charset) } ?? text
      last = m.range.location + m.range.length
      prevWasWord = true
    }
    out += ns.substring(from: last)
    return out.trimmed()
  }

  /** 头部（含折行）→ [小写名字: 值]，同名只留第一个 */
  static func headers(_ raw: String) -> [String: String] {
    var out: [String: String] = [:]
    var cur: (String, String)?
    for line in raw.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n") {
      if line.isEmpty { break }
      if line.first == " " || line.first == "\t" { if cur != nil { cur!.1 += " " + line.trimmed() }; continue }
      if let c = cur, out[c.0] == nil { out[c.0] = c.1 }
      guard let i = line.firstIndex(of: ":") else { cur = nil; continue }
      cur = (String(line[..<i]).trimmed().lowercased(), String(line[line.index(after: i)...]).trimmed())
    }
    if let c = cur, out[c.0] == nil { out[c.0] = c.1 }
    return out
  }

  private static let dateFormats: [DateFormatter] = ["EEE, d MMM yyyy HH:mm:ss Z", "d MMM yyyy HH:mm:ss Z", "EEE, d MMM yyyy HH:mm Z", "EEE, d MMM yyyy HH:mm:ss zzz"].map {
    let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = $0; return f
  }

  /** RFC 2822 的时间（Tue, 20 Oct 2026 13:18:55 +0800 (CST)）→ 毫秒 */
  static func date(_ s: String?) -> Double? {
    guard let s else { return nil }
    let t = s.replace("\\s*\\([^)]*\\)\\s*$", "").replace("\\s+", " ").trimmed()
    for f in dateFormats { if let d = f.date(from: t) { return d.timeIntervalSince1970 * 1000 } }
    return nil
  }

  /** 一封邮件的头部 → 列表里的一行 */
  static func item(headers raw: String, id: String, account: String) -> MailItem {
    let h = headers(raw)
    let who = MailAPI.parseSender(decodeHeader(h["from"] ?? ""))
    let subject = decodeHeader(h["subject"] ?? "")
    return MailItem(name: who.name, email: who.email, subject: subject.isEmpty ? L("（无主题）") : subject, ts: date(h["date"]),
                    id: id, account: account, msgid: (h["message-id"] ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "<> ")))
  }

  /** 整封原始邮件 → 正文纯文字（multipart 里优先 text/plain） */
  static func body(_ raw: Data) -> String {
    let text = String(decoding: raw, as: UTF8.self)
    return part(text, raw: raw).replacingOccurrences(of: "\r\n", with: "\n").replace("[ \\t]+\\n", "\n").replace("\\n{3,}", "\n\n").trimmed()
  }

  private static func split(_ s: String) -> (head: String, body: String) {
    let n = s.replacingOccurrences(of: "\r\n", with: "\n")
    guard let r = n.range(of: "\n\n") else { return (n, "") }
    return (String(n[..<r.lowerBound]), String(n[r.upperBound...]))
  }

  private static func param(_ v: String, _ name: String) -> String? {
    v.match("(?i)\(name)\\s*=\\s*\"?([^\";]+)\"?")?[1]?.trimmed()
  }

  private static func part(_ s: String, raw: Data?) -> String {
    let (head, body) = split(s)
    let h = headers(head + "\n")
    let ctype = h["content-type"] ?? "text/plain"
    let lower = ctype.lowercased()
    if lower.hasPrefix("multipart/"), let boundary = param(ctype, "boundary") {
      let pieces = body.components(separatedBy: "--" + boundary).dropFirst().filter { !$0.hasPrefix("--") }
      let parts = pieces.map { String($0.drop { $0 == "\n" || $0 == "\r" }) }
      // 先找 text/plain，再找 text/html，再递归
      if let p = parts.first(where: { split($0).head.lowercased().contains("text/plain") }) { return part(p, raw: nil) }
      if let p = parts.first(where: { split($0).head.lowercased().contains("text/html") }) { return part(p, raw: nil) }
      for p in parts { let t = part(p, raw: nil); if !t.isEmpty { return t } }
      return ""
    }
    guard lower.hasPrefix("text/") || !h.keys.contains("content-type") else { return "" }
    let charset = param(ctype, "charset") ?? "utf-8"
    let cte = (h["content-transfer-encoding"] ?? "").lowercased()
    var data: Data
    if cte.contains("base64") { data = Data(base64Encoded: body.replace("\\s+", ""), options: .ignoreUnknownCharacters) ?? Data(body.utf8) }
    else if cte.contains("quoted-printable") { data = qp(body) }
    else if let raw, let r = raw.range(of: Data("\r\n\r\n".utf8)) ?? raw.range(of: Data("\n\n".utf8)) { data = raw[r.upperBound...] }   // 8bit：用原始字节按 charset 解
    else { data = Data(body.utf8) }
    if !cte.contains("base64") && !cte.contains("quoted-printable") && raw == nil { return lower.contains("html") ? html(body) : body }
    let t = decode(data, charset: charset)
    return lower.contains("html") ? html(t) : t
  }

  /** HTML → 纯文字（去掉样式、脚本、标签，段落变换行） */
  static func html(_ s: String) -> String {
    s.replace("(?is)<(style|script|head)[^>]*>.*?</\\1>", "")
      .replace("(?i)<br\\s*/?>|</p>|</div>|</tr>|</li>", "\n")
      .replace("<[^>]+>", "")
      .replacingOccurrences(of: "&nbsp;", with: " ").replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&lt;", with: "<")
      .replacingOccurrences(of: "&gt;", with: ">").replacingOccurrences(of: "&quot;", with: "\"").replacingOccurrences(of: "&#39;", with: "'")
      .replace("[ \\t]+", " ")
  }
}

// —— IMAP：常见邮箱的服务器地址，和「怎么生成应用专用密码」的链接 ——
struct MailProvider { let id: String, name: String, host: String, port: Int, help: String, web: String }

enum IMAPProviders {
  static let all: [MailProvider] = [
    MailProvider(id: "gmail", name: "Gmail", host: "imap.gmail.com", port: 993, help: "https://myaccount.google.com/apppasswords", web: "https://mail.google.com/mail/u/0/#search/rfc822msgid%3A"),
    MailProvider(id: "icloud", name: "iCloud", host: "imap.mail.me.com", port: 993, help: "https://account.apple.com/account/manage", web: "https://www.icloud.com/mail"),
    MailProvider(id: "outlook", name: "Outlook / Hotmail", host: "outlook.office365.com", port: 993, help: "https://account.live.com/proofs/AppPassword", web: "https://outlook.live.com/mail/"),
    MailProvider(id: "qq", name: "QQ 邮箱", host: "imap.qq.com", port: 993, help: "https://wx.mail.qq.com/", web: "https://wx.mail.qq.com/"),
    MailProvider(id: "163", name: "网易 163", host: "imap.163.com", port: 993, help: "https://mail.163.com/", web: "https://mail.163.com/"),
    MailProvider(id: "yahoo", name: "Yahoo", host: "imap.mail.yahoo.com", port: 993, help: "https://login.yahoo.com/account/security", web: "https://mail.yahoo.com/"),
    MailProvider(id: "custom", name: "其他", host: "", port: 993, help: "", web: ""),
  ]
  static func by(_ id: String?) -> MailProvider { all.first { $0.id == id } ?? all[0] }
  /** 从邮箱地址猜服务商 */
  static func guess(_ email: String) -> String {
    let d = email.lowercased().components(separatedBy: "@").last ?? ""
    if d.contains("gmail") || d.contains("googlemail") { return "gmail" }
    if d.contains("icloud") || d.contains("me.com") || d.contains("mac.com") { return "icloud" }
    if d.contains("outlook") || d.contains("hotmail") || d.contains("live.") { return "outlook" }
    if d.contains("qq.com") || d.contains("foxmail") { return "qq" }
    if d.contains("163.com") || d.contains("126.com") { return "163" }
    if d.contains("yahoo") { return "yahoo" }
    return "custom"
  }

  /** IMAP 的字符串参数要加引号、转义 */
  static func quote(_ s: String) -> String { "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\"" }

  /** * SEARCH 1 5 9 → [1, 5, 9] */
  static func searchUIDs(_ text: String) -> [Int] {
    text.components(separatedBy: "\n").filter { $0.hasPrefix("* SEARCH") }.flatMap { $0.dropFirst(8).split(separator: " ").compactMap { Int(String($0).trimmed()) } }
  }

  /** FETCH 回来的整段字节 → [(UID, 那块内容)]：每个 {n} 字面量后面跟着 n 个字节。
   *  UID 一般写在字面量前面（「* 3 FETCH (UID 57 BODY[...] {120}」），有的服务器写在后面，两边都找 */
  static func literals(_ data: Data) -> [(uid: Int, block: Data)] {
    let bytes = [UInt8](data)
    var out: [(Int, Data)] = []
    var lineStart = 0, idx = 0
    while idx < bytes.count {
      if bytes[idx] == UInt8(ascii: "{") {
        var j = idx + 1, n = 0, digits = 0
        while j < bytes.count, bytes[j] >= 48, bytes[j] <= 57 { n = n * 10 + Int(bytes[j] - 48); j += 1; digits += 1 }
        if digits > 0, j + 2 < bytes.count, bytes[j] == UInt8(ascii: "}"), bytes[j + 1] == 13, bytes[j + 2] == 10 {
          let before = String(decoding: bytes[lineStart..<idx], as: UTF8.self)
          let start = j + 3, end = min(bytes.count, start + n)
          var lineEnd = end
          while lineEnd < bytes.count && bytes[lineEnd] != 10 { lineEnd += 1 }
          let after = String(decoding: bytes[end..<lineEnd], as: UTF8.self)
          let uid = Int(before.match("UID (\\d+)")?[1] ?? after.match("UID (\\d+)")?[1] ?? "") ?? 0
          out.append((uid, Data(bytes[start..<end])))
          idx = end
          lineStart = end
          continue
        }
      }
      if bytes[idx] == 10 { lineStart = idx + 1 }
      idx += 1
    }
    return out
  }
}
