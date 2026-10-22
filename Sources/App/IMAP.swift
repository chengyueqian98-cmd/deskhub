// IMAP 收信（Gmail、iCloud、Outlook、QQ、163……）：用系统的 Network 框架直连 993 端口（TLS），只读——
// 用 EXAMINE 打开收件箱、用 BODY.PEEK 取内容，所以不会把邮件标成已读，也不会改、删、发任何东西。
// 密码是邮箱的「应用专用密码」，存在系统钥匙串里，不进设置文件。
import Foundation
import Network

final class IMAPConnection {
  private let conn: NWConnection
  private var buf = Data()
  private var n = 0
  private let queue = DispatchQueue(label: "deskhub.imap")

  struct Failure: LocalizedError { let message: String; var errorDescription: String? { message } }

  init(host: String, port: Int) {
    conn = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(integerLiteral: UInt16(port)), using: .tls)
  }

  func open(timeout: TimeInterval = 15) async throws {
    try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
      var done = false
      let finish: (Error?) -> Void = { e in
        guard !done else { return }
        done = true
        if let e { cont.resume(throwing: e) } else { cont.resume() }
      }
      conn.stateUpdateHandler = { st in
        switch st {
        case .ready: finish(nil)
        case .failed(let e): finish(Failure(message: L("连不上邮箱服务器：") + e.localizedDescription))
        case .waiting(let e): finish(Failure(message: L("连不上邮箱服务器：") + e.localizedDescription))
        default: break
        }
      }
      conn.start(queue: queue)
      queue.asyncAfter(deadline: .now() + timeout) { finish(Failure(message: L("连接邮箱服务器超时"))) }
    }
    _ = try await readUntil { $0.range(of: Data("\r\n".utf8)) != nil }   // 欢迎语
  }

  func close() { conn.cancel() }

  private func receive() async throws -> Data {
    try await withCheckedThrowingContinuation { cont in
      conn.receive(minimumIncompleteLength: 1, maximumLength: 1 << 16) { data, _, eof, err in
        if let err { cont.resume(throwing: err) }
        else if let data, !data.isEmpty { cont.resume(returning: data) }
        else if eof { cont.resume(throwing: Failure(message: L("邮箱服务器断开了连接"))) }
        else { cont.resume(returning: Data()) }
      }
    }
  }

  private func readUntil(_ done: (Data) -> Bool) async throws -> Data {
    while !done(buf) {
      buf.append(try await receive())
      if buf.count > 8 << 20 { throw Failure(message: L("邮件太大了")) }
    }
    let out = buf
    buf = Data()
    return out
  }

  /** 发一条命令，读到这条命令的结束行（a12 OK / NO / BAD）为止，返回全部字节 */
  @discardableResult
  func command(_ c: String, secret: Bool = false) async throws -> Data {
    n += 1
    let tag = "a\(n)"
    let line = "\(tag) \(c)\r\n"
    try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
      conn.send(content: Data(line.utf8), completion: .contentProcessed { e in if let e { cont.resume(throwing: e) } else { cont.resume() } })
    }
    let marker = Data("\r\n\(tag) ".utf8), first = Data("\(tag) ".utf8)
    let data = try await readUntil { d in
      guard let r = d.range(of: marker, options: .backwards) ?? (d.starts(with: first) ? d.startIndex..<d.startIndex : nil) else { return false }
      return d[r.upperBound...].range(of: Data("\r\n".utf8)) != nil || d.starts(with: first) && d.range(of: Data("\r\n".utf8)) != nil
    }
    let text = String(decoding: data.suffix(400), as: UTF8.self)
    if let m = text.match("\(tag) (NO|BAD) ([^\\r\\n]*)") {
      throw Failure(message: (m[2] ?? "").isEmpty ? L("邮箱服务器拒绝了请求") : m[2]!)
    }
    _ = secret
    return data
  }
}

enum IMAPMail {
  static let keychainService = "com.qianshengyue.desktophub.mail"

  struct Account { var email: String, provider: MailProvider, host: String, port: Int }

  static func account(_ store: Store) -> Account? {
    let m = store.data["mail"] as? JSON ?? [:]
    guard m["source"] as? String == "imap", let email = m["email"] as? String, !email.isEmpty else { return nil }
    let p = IMAPProviders.by(m["provider"] as? String ?? IMAPProviders.guess(email))
    let host = (m["host"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? p.host
    return Account(email: email, provider: p, host: host, port: Int(num(m["port"]) ?? Double(p.port)))
  }

  /** 登录（密码错了给一句人话）并只读打开收件箱 */
  private static func login(_ a: Account) async throws -> IMAPConnection {
    guard let pass = Keychain.read(service: keychainService, account: a.email) else { throw IMAPConnection.Failure(message: L("还没填邮箱的应用专用密码：到「设置 → 邮件」里填")) }
    guard !a.host.isEmpty else { throw IMAPConnection.Failure(message: L("还没填 IMAP 服务器地址")) }
    let c = IMAPConnection(host: a.host, port: a.port)
    try await c.open()
    // 网易邮箱要求先报一下客户端身份，否则后面的命令会被拒绝；别的服务器不认识也没关系
    _ = try? await c.command("ID (\"name\" \"Glancedesk\" \"version\" \"1.0\")")
    do { try await c.command("LOGIN \(IMAPProviders.quote(a.email)) \(IMAPProviders.quote(pass))", secret: true) } catch {
      c.close()
      throw IMAPConnection.Failure(message: L("邮箱登录失败：大多数邮箱要用「应用专用密码 / 授权码」，不是网页登录密码。") + " (\(error.localizedDescription))")
    }
    try await c.command("EXAMINE INBOX")
    return c
  }

  /** 未读邮件：总数 + 最近 12 封的发件人、主题、时间（只取头部，不取正文） */
  static func unread(_ a: Account, limit: Int = 12) async -> MailState {
    do {
      let c = try await login(a)
      defer { c.close() }
      let uids = IMAPProviders.searchUIDs(String(decoding: try await c.command("UID SEARCH UNSEEN"), as: UTF8.self))
      let pick = uids.suffix(limit)
      var items: [MailItem] = []
      if !pick.isEmpty {
        let d = try await c.command("UID FETCH \(pick.map(String.init).joined(separator: ",")) (UID BODY.PEEK[HEADER.FIELDS (FROM SUBJECT DATE MESSAGE-ID)])")
        items = IMAPProviders.literals(d).map { Mime.item(headers: String(decoding: $0.block, as: UTF8.self), id: "imap:\($0.uid)", account: a.provider.name) }
      }
      _ = try? await c.command("LOGOUT")
      return MailState(ok: true, unread: uids.count, items: items.sorted { ($0.ts ?? 0) > ($1.ts ?? 0) })
    } catch {
      return MailState(ok: false, error: error.localizedDescription)
    }
  }

  /** 一封的正文（最多读 300 KB；BODY.PEEK 不会标成已读） */
  static func body(_ a: Account, uid: String) async -> Fetch.MailBody {
    do {
      let c = try await login(a)
      defer { c.close() }
      let d = try await c.command("UID FETCH \(uid) (UID BODY.PEEK[]<0.300000>)")
      guard let raw = IMAPProviders.literals(d).first?.block else { return .failed(L("在邮箱里没找到这封邮件（可能已经被移走或删除）")) }
      _ = try? await c.command("LOGOUT")
      let it = Mime.item(headers: String(decoding: raw.prefix(64 * 1024), as: UTF8.self), id: "imap:\(uid)", account: a.provider.name)
      return .ok(name: it.name, email: it.email, subject: it.subject, body: String(Mime.body(raw).prefix(8000)))
    } catch {
      return .failed(error.localizedDescription)
    }
  }

  /** 设置页的「测试连接」 */
  static func test(_ a: Account) async -> String? {
    do { let c = try await login(a); _ = try? await c.command("LOGOUT"); c.close(); return nil } catch { return error.localizedDescription }
  }

  /** 在网页里打开这封（Gmail 能直接定位到这封，其它邮箱打开收件箱） */
  static func webURL(_ a: Account, msgid: String) -> String {
    a.provider.id == "gmail" && !msgid.isEmpty ? a.provider.web + (msgid.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? msgid) : (a.provider.web.isEmpty ? "" : a.provider.web)
  }
}
