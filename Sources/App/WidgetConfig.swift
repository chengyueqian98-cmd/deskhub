// 每个组件自己的设置（编辑态里组件右上角的齿轮）：同一种可以加好几个，各看各的。
// 存在 desk.json 的 widgetConfig[组件 id] 里。
import SwiftUI

enum WidgetConfig {
  static let configurable: Set<String> = ["market", "weather", "worldclock", "news", "todo", "countdown", "crypto", "github", "rss", "photo", "pomodoro"]
}

struct WidgetConfigPanel: View {
  @Environment(\.pal) var pal
  @ObservedObject var model: DeskModel
  let id: String
  @State private var c: JSON = [:]
  @State private var name = ""
  @State private var cityQ = ""
  @State private var cities: [(name: String, lat: Double, lon: Double, region: String)] = []

  var body: some View {
    let type = typeOf(id)
    SidePanel(close: save) {
      VStack(alignment: .leading, spacing: 14) {
        Text(widgetDef(type)?.name ?? id).font(Font2.ui(20, .semibold)).foregroundStyle(pal.text)
        field(L("显示的名字")) {
          TextField(widgetDef(type)?.name ?? "", text: $name).textFieldStyle(.roundedBorder).frame(width: 240)
        }
        switch type {
        case "market":
          field(L("看哪些（代码，用逗号分开；留空 = 全部自选）")) {
            TextField("sh000001, rt_hk00700, AAPL", text: list("keys")).textFieldStyle(.roundedBorder)
          }
          Note(text: L("A 股填 6 位数字，港股填 5 位数字，美股填字母代码。想加名字（比如「腾讯」）请用市场页的「添加」。"))
        case "weather":
          field(L("城市（留空 = 设置里的那个城市）")) {
            HStack {
              TextField(L("输入城市名"), text: $cityQ).textFieldStyle(.roundedBorder).frame(width: 220).onSubmit(search)
              Button(L("搜索"), action: search).buttonStyle(MiniButton())
            }
          }
          if let cur = c["city"] as? JSON { Text(L("现在：") + (cur["name"] as? String ?? "")).font(Font2.ui(12)).foregroundStyle(pal.text3) }
          ForEach(Array(cities.enumerated()), id: \.offset) { _, x in
            Button("\(x.name)  \(x.region)") { c["city"] = ["name": x.name, "lat": x.lat, "lon": x.lon]; cities = [] }.buttonStyle(MiniButton())
          }
        case "worldclock":
          field(L("显示哪些城市")) {
            let on = c["zones"] as? [String] ?? ["Asia/Shanghai"]
            FlowRow(ZONES.map { ($0.id, appLang == "en" ? $0.en : $0.name) }) { zid, n in
              Button(n) { c["zones"] = on.contains(zid) ? on.filter { $0 != zid } : on + [zid] }.buttonStyle(ChipStyle(on: on.contains(zid)))
            }
          }
        case "news":
          field(L("只看这个分类（不选 = 全部）")) {
            let tag = c["tag"] as? String ?? ""
            HStack { ForEach(["", "财经", "科技", "国际", "大中华", "本地"], id: \.self) { t in Button(t.isEmpty ? L("全部") : L(t)) { c["tag"] = t }.buttonStyle(ChipStyle(on: tag == t)) } }
          }
          Note(text: L("新闻来源在「设置 → AI 与数据源」里统一选。"))
        case "todo":
          field(L("只看哪个列表")) {
            let cur = c["list"] as? String ?? ""
            VStack(alignment: .leading, spacing: 6) {
              Button(L("全部列表")) { c["list"] = "" }.buttonStyle(ChipStyle(on: cur.isEmpty))
              ForEach(model.todos?.lists ?? [], id: \.id) { l in Button(l.title) { c["list"] = l.id }.buttonStyle(ChipStyle(on: cur == l.id)) }
            }
          }
          Note(text: L("待办来自系统的「提醒事项」App。在浮层里点圆圈就是标成已完成。"))
        case "countdown":
          CountdownEditor(items: Binding(get: { c["items"] as? [JSON] ?? [] }, set: { c["items"] = $0 }))
        case "crypto":
          field(L("币种（简写或 CoinGecko 的 id，用逗号分开）")) {
            TextField("btc, eth, sol", text: list("coins")).textFieldStyle(.roundedBorder)
          }
          field(L("计价")) {
            let vs = c["vs"] as? String ?? "usd"
            HStack { ForEach(["usd", "cny", "hkd", "eur"], id: \.self) { v in Button(v.uppercased()) { c["vs"] = v }.buttonStyle(ChipStyle(on: vs == v)) } }
          }
          Note(text: L("数据来自 CoinGecko 公开接口，两分钟刷新一次，只做展示。"))
        case "github":
          field(L("仓库（拥有者/仓库名，用逗号分开）")) {
            TextField("apple/swift", text: list("repos")).textFieldStyle(.roundedBorder)
          }
          Note(text: L("显示 Star、Fork、Issue 和所有安装包的下载次数（GitHub 自带的计数）。不登录每小时只能查 60 次，所以半小时刷新一次。"))
        case "rss":
          field(L("订阅地址（RSS 或 Atom）")) {
            TextField("https://…/feed.xml", text: str("url")).textFieldStyle(.roundedBorder)
          }
        case "photo":
          field(L("照片文件夹")) {
            HStack {
              Text(c["folder"] as? String ?? (NSHomeDirectory() + "/Pictures")).font(Font2.ui(12)).foregroundStyle(pal.text2).lineLimit(1).truncationMode(.middle)
              Button(L("选择…")) {
                let p = NSOpenPanel()
                p.canChooseDirectories = true; p.canChooseFiles = false
                if p.runModal() == .OK, let u = p.url { c["folder"] = u.path }
              }.buttonStyle(MiniButton())
            }
          }
          Note(text: L("每半小时换一张；在浮层里点一下照片马上换。"))
        case "pomodoro":
          field(L("一次多久")) {
            let m = num(c["minutes"]) ?? 25
            HStack { ForEach([15.0, 25, 45, 60], id: \.self) { v in Button(L("%@ 分钟", jsNum(v))) { c["minutes"] = v }.buttonStyle(ChipStyle(on: m == v)) } }
          }
        default: EmptyView()
        }
        HStack {
          Button { save() } label: {
            Text(L("完成")).font(Font2.ui(12, .semibold)).foregroundStyle(.white).padding(.horizontal, 16).padding(.vertical, 6).background(Capsule().fill(pal.accent))
          }.buttonStyle(.plain)
          if id != type { Button(L("删掉这个组件")) { model.configOpen = nil; model.removeWidget(id) }.buttonStyle(PillButton()) }
        }.padding(.top, 8)
      }
    }
    .onAppear {
      c = model.store.config(id)
      name = model.editLayout.item(id)?.name ?? ""
    }
  }

  private func save() {
    model.store.setConfig(id, c)
    if name != (model.editLayout.item(id)?.name ?? "") { model.setLayout(rename(model.editLayout.json, id, name.trimmed())) }
    if typeOf(id) == "pomodoro", let m = num(c["minutes"]), !model.pomo.running { model.pomoReset(m) }
    if typeOf(id) == "market" { model.kick("market") }
    model.configOpen = nil
  }

  private func search() {
    let q = cityQ.trimmed()
    guard !q.isEmpty else { return }
    Task { cities = await Fetch.searchCity(q) }
  }

  /** 逗号分开的列表 ↔ 设置里的数组（行情代码会顺手转成新浪代码） */
  private func list(_ k: String) -> Binding<String> {
    Binding(get: { (c[k] as? [String] ?? []).map { k == "keys" ? Market.displayCode($0) : $0 }.joined(separator: ", ") },
            set: { v in
              let parts = v.components(separatedBy: CharacterSet(charactersIn: ",，")).map { $0.trimmed() }.filter { !$0.isEmpty }
              c[k] = k == "keys" ? parts.compactMap { Market.toSinaKey($0) } : parts
            })
  }
  private func str(_ k: String) -> Binding<String> { Binding(get: { c[k] as? String ?? "" }, set: { c[k] = $0.trimmed() }) }

  private func field<C: View>(_ label: String, @ViewBuilder _ content: () -> C) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(label).font(Font2.ui(12)).foregroundStyle(pal.text2)
      content()
    }
  }
}

struct CountdownEditor: View {
  @Environment(\.pal) var pal
  @Binding var items: [JSON]
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(L("日子")).font(Font2.ui(12)).foregroundStyle(pal.text2)
      ForEach(Array(items.enumerated()), id: \.offset) { i, x in
        HStack {
          TextField(L("名字，比如：期末考试"), text: Binding(get: { x["title"] as? String ?? "" }, set: { items[i]["title"] = $0 })).textFieldStyle(.roundedBorder).frame(width: 200)
          DatePicker("", selection: Binding(get: { date(x["date"] as? String) }, set: { items[i]["date"] = key($0) }), displayedComponents: .date).labelsHidden()
          Button { items.remove(at: i) } label: { Image(systemName: "minus.circle") }.buttonStyle(.plain).foregroundStyle(pal.text3)
        }
      }
      Button(L("＋ 加一个日子")) { items.append(["title": "", "date": key(Date().addingTimeInterval(30 * 86400))]) }.buttonStyle(MiniButton())
    }
  }
  private func date(_ s: String?) -> Date {
    let p = (s ?? "").components(separatedBy: "-").compactMap { Int($0) }
    return p.count == 3 ? Date(timeIntervalSince1970: localMs(p[0], p[1], p[2]) / 1000) : Date()
  }
  private func key(_ d: Date) -> String { F.dayKey(d.timeIntervalSince1970 * 1000) }
}

/** 编排条上的「添加组件」：收起的那种直接打开；能加好几个的，再加一个 */
struct AddWidgetMenu: View {
  @Environment(\.pal) var pal
  @ObservedObject var model: DeskModel
  var body: some View {
    let L0 = model.editLayout
    Menu {
      ForEach(WIDGETS, id: \.id) { d in
        let base = L0.item(d.id)
        if base?.on != true {
          Button(d.name) { model.toggleWidget(d.id, true); if WidgetConfig.configurable.contains(d.id) && model.store.config(d.id).isEmpty && ["rss", "github", "countdown"].contains(d.id) { model.configOpen = d.id } }
        } else if d.multi {
          Button(L("再加一个「%@」", d.name)) { model.addWidget(d.id) }
        }
      }
    } label: {
      Text(L("＋ 添加组件")).font(Font2.ui(12, .medium)).foregroundStyle(pal.text).padding(.horizontal, 12).padding(.vertical, 5).background(Capsule().fill(pal.fill2))
    }
    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
  }
}
