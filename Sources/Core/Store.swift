// 设置存储：和 Electron 版共用同一个文件（~/Library/Application Support/桌面信息中心/desk.json），
// 所以自选、城市、布局、计划价、管家名字……换成原生版之后全都还在。
// 只改动自己用到的键，文件里其它键（AI、提醒等第 4 阶段才用的）原样保留。
import Foundation

final class Store {
  let url: URL
  private(set) var data: JSON
  var onChange: ((Set<String>) -> Void)?

  static var defaultURL: URL {
    FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Library/Application Support/桌面信息中心/desk.json")
  }

  init(url: URL = Store.defaultURL) {
    self.url = url
    var saved: JSON = [:]
    if let d = try? Data(contentsOf: url), let j = (try? JSONSerialization.jsonObject(with: d)) as? JSON { saved = j }
    data = saved
  }

  func set(_ patch: JSON) {
    for (k, v) in patch { data[k] = v }
    save()
    onChange?(Set(patch.keys))
  }

  private func save() {
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    guard let d = try? JSONSerialization.data(withJSONObject: data, options: [.prettyPrinted, .withoutEscapingSlashes]) else { return }
    try? d.write(to: url, options: .atomic)    // 先写临时文件再改名，断电也不会写坏
  }

  // —— 带默认值的读取（默认值和 Electron 版 store.js 的 DEFAULTS 一致） ——
  var watch: [String] { data["watch"] as? [String] ?? Market.defaultWatch }
  /** mono 中性（默认，▲ 亮 ▼ 暗）/ rup 红涨绿跌 / gup 绿涨红跌 */
  var colors: String { data["colors"] as? String ?? "mono" }
  var alertPct: Double { num(data["alertPct"]) ?? 3 }
  var priceAlerts: [String: Any] { data["priceAlerts"] as? JSON ?? [:] }
  var plans: [String: Any] { data["plans"] as? JSON ?? [:] }
  var acctSize: Double { num(data["acctSize"]) ?? 0 }
  var maxPerPct: Double { num(data["maxPerPct"]) ?? 20 }
  var city: (name: String, lat: Double, lon: Double) {
    guard let c = data["city"] as? JSON, let lat = num(c["lat"]), let lon = num(c["lon"]) else { return WeatherAPI.defaultCity }
    return (c["name"] as? String ?? "", lat, lon)
  }
  var quantDir: String { data["quantDir"] as? String ?? QuantAPI.defaultDir }
  var hotkey: String { data["hotkey"] as? String ?? "Control+Alt+Space" }
  var layout: Any? { data["layout"] }
  var butlerName: String {
    let n = (data["butlerName"] as? String ?? "").trimmed()
    return n.isEmpty ? "管家" : n
  }
  var butlerSeen: [String: Double] {
    var out: [String: Double] = [:]
    for (k, v) in data["butlerSeen"] as? JSON ?? [:] { if let n = num(v) { out[k] = n } }
    return out
  }
  var newsSources: [String] { data["newsSources"] as? [String] ?? News.defaultIds }
  var riskCodes: [String] { data["riskCodes"] as? [String] ?? [] }
  var riskStopPct: Double { num(data["riskStopPct"]) ?? -8 }
  var onboarded: Bool { (data["onboarded"] as? Bool) == true }
  var lang: String { data["lang"] as? String == "en" ? "en" : "zh" }
  var mailRules: Cands.MailRules {
    let r = data["butlerRules"] as? JSON ?? [:]
    return Cands.MailRules(contacts: r["contacts"] as? [String] ?? [], money: (r["money"] as? Bool) != false)
  }
  var aiMail: Bool { ((data["butlerRules"] as? JSON)?["aiMail"] as? Bool) == true }
  /** 每个组件自己的设置：{ 组件 id: {...} } */
  func config(_ id: String) -> JSON { (data["widgetConfig"] as? JSON)?[id] as? JSON ?? [:] }
  func setConfig(_ id: String, _ c: JSON) {
    var all = data["widgetConfig"] as? JSON ?? [:]
    all[id] = c
    set(["widgetConfig": all])
  }
  /** 开着的提醒，按时间排（管家组件里列前三条） */
  var reminders: [ReminderLine] {
    (data["reminders"] as? [JSON] ?? [])
      .filter { ($0["enabled"] as? Bool) == true }
      .map { ReminderLine(time: $0["time"] as? String ?? "", title: $0["title"] as? String ?? "") }
      .sorted { $0.time < $1.time }
  }
}
