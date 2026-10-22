// 桌面网格布局（从 Electron 版 src/main/desk/layout.js 原样移植，规则一条不改）。
//
// 像苹果小组件那样按「小 / 中 / 大」几档摆，松手吸附，永不重叠，并且会**自动避让、自动复位**：
//   S 小 1×1 · M 中 2×1 · L 大 2×2 · T 高 2×3 · W 宽 4×1 · XL 特大 4×2
// 一屏 8 列 × 4 行：格子宽度按屏宽算、高度按屏高算，默认布局正好铺满。
//
// 每个组件除了「现在的位置」col/row，还记着「原位」hc/hr 和「最近被动过的先后」pri：
//   · 拖动、换档、打开它的那一刻，位置成为新的原位，并拿到最高优先级；
//   · 别的组件被挤到时，就近让到离自己原位最近的空位（一屏之内）；
//   · 每次整理都从原位重算，挤它的组件挪走后，被挤开的会自动回到原位。
// 这一层是纯函数，存盘格式和 Electron 版一样（desk.json 的 layout），两个版本能互相读。
import Foundation

enum Grid {
  static let cols = 8
  static let rows = 4
  static let gap = 16.0
  static let cellMin = 120.0, cellMax = 260.0
  static let rowMin = 110.0, rowMax = 300.0
  static let version = 4
}

struct SizeSpec { let w: Int, h: Int, label: String }

let SIZES: [String: SizeSpec] = [
  "S": SizeSpec(w: 1, h: 1, label: "小"),
  "M": SizeSpec(w: 2, h: 1, label: "中"),
  "L": SizeSpec(w: 2, h: 2, label: "大"),
  "T": SizeSpec(w: 2, h: 3, label: "高"),
  "W": SizeSpec(w: 4, h: 1, label: "宽"),
  "XL": SizeSpec(w: 4, h: 2, label: "特大"),
]

struct WidgetDef {
  let id: String, label: String, size: String, sizes: [String]
  var multi = false      // 能不能加好几个（每个各自设置，比如两个行情：一个 A 股、一个美股）
  var labelEn = ""
  var name: String { appLang == "en" && !labelEn.isEmpty ? labelEn : label }
}

/** 组件登记表：sizes 是允许的档位，size 是默认档。id 就是组件的「种类」 */
let WIDGETS: [WidgetDef] = [
  WidgetDef(id: "clock", label: "时钟", size: "M", sizes: ["S", "M"], labelEn: "Clock"),
  WidgetDef(id: "butler", label: "管家", size: "M", sizes: ["M", "L", "W"], labelEn: "Butler"),
  WidgetDef(id: "weather", label: "天气", size: "M", sizes: ["S", "M"], multi: true, labelEn: "Weather"),
  WidgetDef(id: "market", label: "行情", size: "L", sizes: ["M", "L", "T"], multi: true, labelEn: "Stocks"),
  WidgetDef(id: "calendar", label: "日历", size: "L", sizes: ["L", "T"], labelEn: "Calendar"),
  WidgetDef(id: "mail", label: "邮件", size: "M", sizes: ["M", "L", "T"], labelEn: "Mail"),
  WidgetDef(id: "news", label: "新闻", size: "L", sizes: ["M", "L", "T"], labelEn: "News"),
  WidgetDef(id: "worldclock", label: "世界时钟", size: "M", sizes: ["S", "M"], multi: true, labelEn: "World Clock"),
  WidgetDef(id: "risk", label: "风控", size: "M", sizes: ["M", "L"], labelEn: "Risk"),
  WidgetDef(id: "todo", label: "待办", size: "L", sizes: ["M", "L", "T"], multi: true, labelEn: "To-dos"),
  WidgetDef(id: "countdown", label: "倒数日", size: "M", sizes: ["S", "M", "L"], multi: true, labelEn: "Countdown"),
  WidgetDef(id: "crypto", label: "加密货币", size: "M", sizes: ["M", "L"], multi: true, labelEn: "Crypto"),
  WidgetDef(id: "github", label: "GitHub", size: "M", sizes: ["M", "L"], multi: true, labelEn: "GitHub"),
  WidgetDef(id: "rss", label: "订阅", size: "L", sizes: ["M", "L", "T"], multi: true, labelEn: "Feed"),
  WidgetDef(id: "photo", label: "照片", size: "L", sizes: ["S", "M", "L", "T", "W", "XL"], multi: true, labelEn: "Photos"),
  WidgetDef(id: "pomodoro", label: "番茄钟", size: "S", sizes: ["S", "M"], labelEn: "Focus Timer"),
]

/** 按种类找登记项。用数组查找而不是字典，不会有 JS 那种 `__proto__` 取到原型的问题 */
func widgetDef(_ type: String) -> WidgetDef? { WIDGETS.first { $0.id == type } }

/** 实例 id → 种类：「market」「market-2」都是行情 */
func typeOf(_ id: String) -> String {
  if widgetDef(id) != nil { return id }
  if let r = id.range(of: "-", options: .backwards), widgetDef(String(id[..<r.lowerBound])) != nil, Int(id[r.upperBound...]) != nil { return String(id[..<r.lowerBound]) }
  return id
}

struct LayoutItem: Equatable {
  var id: String
  var type: String = ""
  var on: Bool
  var col: Int, row: Int
  var hc: Int, hr: Int
  var pri: Double
  var size: String
  var w: Int, h: Int
  var name: String

  var json: JSON {
    ["id": id, "type": type, "on": on, "col": col, "row": row, "hc": hc, "hr": hr, "pri": pri, "size": size, "w": w, "h": h, "name": name]
  }
}

struct Layout: Equatable {
  var items: [LayoutItem]
  func item(_ id: String) -> LayoutItem? { items.first { $0.id == id } }
  var json: JSON { ["version": Grid.version, "cols": Grid.cols, "items": items.map(\.json)] }
}

/** 默认布局：中间留空露出壁纸，左右两侧各一列、每列正好 4 行。新闻、世界时钟、风控默认关着 */
let DEFAULT_LAYOUT: JSON = [
  "version": Grid.version,
  "cols": Grid.cols,
  "items": [
    ["id": "clock", "on": true, "col": 0, "row": 0, "size": "M"],
    ["id": "butler", "on": true, "col": 0, "row": 1, "size": "M"],
    ["id": "market", "on": true, "col": 0, "row": 2, "size": "L"],
    ["id": "weather", "on": true, "col": 6, "row": 0, "size": "M"],
    ["id": "calendar", "on": true, "col": 6, "row": 1, "size": "L"],
    ["id": "mail", "on": true, "col": 6, "row": 3, "size": "M"],
    ["id": "news", "on": false, "col": 2, "row": 0, "size": "L"],
    ["id": "worldclock", "on": false, "col": 4, "row": 3, "size": "M"],
    ["id": "risk", "on": false, "col": 4, "row": 2, "size": "M"],
  ] as [JSON],
]

private func clampInt(_ v: Any?, _ lo: Int, _ hi: Int, _ dflt: Int) -> Int {
  guard let d = num(v) else { return dflt }
  return min(hi, max(lo, Int(d.rounded())))
}

/** 组件的尺寸（格）。档位不在允许范围内就退回默认档 */
func dims(_ id: String, _ size: String?) -> (size: String?, w: Int, h: Int) {
  let def = widgetDef(id)
  let key: String? = def.map { d in size.flatMap { d.sizes.contains($0) ? $0 : nil } ?? d.size }
  let s = key.flatMap { SIZES[$0] } ?? SIZES["M"]!
  return (key, s.w, s.h)
}

private func norm1(_ raw: Any?) -> LayoutItem? {
  guard let o = raw as? JSON, let id = o["id"] as? String else { return nil }
  let type = typeOf(id)
  guard let def = widgetDef(type), id == type || def.multi else { return nil }
  let d = dims(type, o["size"] as? String)
  let col = clampInt(o["col"], 0, Grid.cols - d.w, 0)
  let row = clampInt(o["row"], 0, 200, 0)
  return LayoutItem(
    id: id,
    type: type,
    on: (o["on"] as? Bool) != false,
    col: col, row: row,
    hc: clampInt(o["hc"], 0, Grid.cols - d.w, col),
    hr: clampInt(o["hr"], 0, 200, row),
    pri: num(o["pri"]) ?? 0,
    size: d.size!, w: d.w, h: d.h,
    name: (o["name"] as? String)?.head(20) ?? ""
  )
}

func overlaps(_ a: (col: Int, row: Int, w: Int, h: Int), _ b: (col: Int, row: Int, w: Int, h: Int)) -> Bool {
  a.col < b.col + b.w && b.col < a.col + a.w && a.row < b.row + b.h && b.row < a.row + a.h
}
private func box(_ i: LayoutItem) -> (col: Int, row: Int, w: Int, h: Int) { (i.col, i.row, i.w, i.h) }

private func hits(_ placed: [LayoutItem], _ b: (col: Int, row: Int, w: Int, h: Int)) -> Bool {
  placed.contains { $0.on && overlaps(b, box($0)) }
}

/** 一屏之内离 (col,row) 最近的空位（曼哈顿距离，同距离取靠上靠左）；一屏放不下返回 nil */
private func nearestSlot(_ placed: [LayoutItem], _ w: Int, _ h: Int, _ col: Int, _ row: Int) -> (col: Int, row: Int)? {
  var best: (col: Int, row: Int, dist: Int)?
  var r = 0
  while r + h <= Grid.rows {
    var c = 0
    while c + w <= Grid.cols {
      if !hits(placed, (c, r, w, h)) {
        let dist = abs(c - col) + abs(r - row)
        if best == nil || dist < best!.dist { best = (c, r, dist) }
      }
      c += 1
    }
    r += 1
  }
  return best.map { ($0.col, $0.row) }
}

/** 一屏已经放不下时的兜底：从原位往下找第一个放得下的空位（会落到屏幕外面，但至少不重叠） */
private func pushDown(_ placed: [LayoutItem], _ w: Int, _ h: Int, _ col: Int, _ row: Int) -> Int {
  var r = max(0, row)
  for _ in 0..<400 {
    guard let hit = placed.first(where: { $0.on && overlaps((col, r, w, h), box($0)) }) else { return r }
    r = hit.row + hit.h
  }
  return r
}

/** 把整份布局修成合法的：补齐缺的组件、夹住越界，然后按优先级逐个摆放。
 *  priority 指定的组件排最前（拖动 / 换档时它就是「被操作的那个」） */
func normalize(_ layout: Any?, priority: String? = nil) -> Layout {
  let obj = layout as? JSON
  let src = obj?["items"] as? [Any] ?? []
  // 旧版（12 列自由尺寸）的坐标换算不过来：位置回到默认，但「开着/收起」和「改过的名字」保留
  let legacy = !src.isEmpty && (num(obj?["version"]).map { Int($0) } ?? -1) != Grid.version
  let first = src.isEmpty
  var byId: [String: LayoutItem] = [:]
  var extras: [LayoutItem] = []      // 同一种加的第二个、第三个……（旧版布局迁移时不带）
  for it in src {
    guard let n = norm1(it) else { continue }
    if n.id == n.type { byId[n.id] = n } else if !legacy && !extras.contains(where: { $0.id == n.id }) { extras.append(n) }
  }
  let defaults = DEFAULT_LAYOUT["items"] as! [JSON]

  var items: [LayoutItem] = []
  for def in WIDGETS {
    let got = byId[def.id]
    let d = defaults.first { $0["id"] as? String == def.id }
    if let got, !legacy { items.append(got); continue }
    if let got, legacy {
      var dd = d ?? ["id": def.id, "size": def.size]
      dd["name"] = got.name
      var n = norm1(dd)!
      n.on = got.on
      items.append(n)
      continue
    }
    // 补齐没见过的组件：第一次跑用默认布局；之后新加的组件默认关着，不往别人已经占好的位置上硬塞
    var n = norm1(d ?? ["id": def.id, "size": def.size])!
    n.name = ""
    if !(first && d != nil) { n.on = false }
    items.append(n)
  }
  return place(items + extras, priority: priority)
}

private func place(_ items: [LayoutItem], priority: String?) -> Layout {
  func cmp(_ a: (Int, LayoutItem), _ b: (Int, LayoutItem)) -> Bool {
    let (ia, x) = a, (ib, y) = b
    if x.id != y.id {
      if x.id == priority { return true }
      if y.id == priority { return false }
    }
    if x.pri != y.pri { return x.pri > y.pri }
    if x.hr != y.hr { return x.hr < y.hr }
    if x.hc != y.hc { return x.hc < y.hc }
    return ia < ib    // 稳定排序：和 JS 的 Array.sort 一样，平手时保持原来的顺序
  }
  let order = items.enumerated().map { ($0.offset, $0.element) }.sorted(by: cmp).map(\.1)

  var placed: [LayoutItem] = []
  for var it in order {
    // 原位夹在一屏之内（原位掉到屏幕外面的老数据也能拉回来）
    let home = (col: min(it.hc, Grid.cols - it.w), row: min(it.hr, max(0, Grid.rows - it.h)))
    if !it.on { it.col = home.col; it.row = home.row; placed.append(it); continue }
    if !hits(placed, (home.col, home.row, it.w, it.h)) {
      it.col = home.col; it.row = home.row
    } else if let near = nearestSlot(placed, it.w, it.h, home.col, home.row) {
      it.col = near.col; it.row = near.row
    } else {
      it.col = home.col; it.row = pushDown(placed, it.w, it.h, home.col, home.row)
    }
    placed.append(it)
  }
  // 还原成登记表的顺序（加的那些排在后面，按原来的先后），输出稳定
  return Layout(items: items.compactMap { i in placed.first { $0.id == i.id } })
}

private func nextPri(_ L: Layout) -> Double { (L.items.map(\.pri).max() ?? 0) + 1 }

/** 拖动：挪到 (col,row)，它拿到最高优先级，新位置成为原位；撞到的组件就近让开 */
func move(_ layout: Any?, _ id: String, _ col: Int, _ row: Int) -> Layout {
  var L = normalize(layout)
  guard let i = L.items.firstIndex(where: { $0.id == id }) else { return L }
  let pri = nextPri(L)
  var it = L.items[i]
  it.col = min(Grid.cols - it.w, max(0, col))
  it.row = min(max(0, Grid.rows - it.h), max(0, row))
  it.hc = it.col; it.hr = it.row
  it.on = true
  it.pri = pri
  L.items[i] = it
  return normalize(L.json, priority: id)
}

/** 换档：只能换成允许的档位；变宽后超出右边就贴回来；撞到别人由对方就近让位 */
func setSize(_ layout: Any?, _ id: String, _ size: String) -> Layout {
  var L = normalize(layout)
  guard let i = L.items.firstIndex(where: { $0.id == id }), let def = widgetDef(L.items[i].type), def.sizes.contains(size) else { return L }
  let pri = nextPri(L)
  let d = dims(def.id, size)
  var it = L.items[i]
  it.size = d.size!; it.w = d.w; it.h = d.h
  it.col = min(it.col, Grid.cols - it.w)
  it.row = min(it.row, max(0, Grid.rows - it.h))
  it.hc = it.col; it.hr = it.row
  it.on = true
  it.pri = pri
  L.items[i] = it
  return normalize(L.json, priority: id)
}

/** 一屏里第一个放得下 w×h 的空位；没有就 nil */
private func slotFor(_ items: [LayoutItem], _ me: String, _ w: Int, _ h: Int) -> (col: Int, row: Int)? {
  let others = items.filter { $0.id != me && $0.on }
  var row = 0
  while row + h <= Grid.rows {
    var col = 0
    while col + w <= Grid.cols {
      if !others.contains(where: { overlaps((col, row, w, h), box($0)) }) { return (col, row) }
      col += 1
    }
    row += 1
  }
  return nil
}

/** 开关一个组件。打开时先找一屏里的空位；一屏已经铺满就把「高」收成「大」腾出一行，再找一次 */
func toggle(_ layout: Any?, _ id: String, _ on: Bool) -> Layout {
  var L = normalize(layout)
  guard let i = L.items.firstIndex(where: { $0.id == id }) else { return L }
  L.items[i].on = on
  if on {
    var spot = slotFor(L.items, id, L.items[i].w, L.items[i].h)
    if spot == nil && L.items.contains(where: { $0.on && $0.size == "T" }) {
      for k in L.items.indices where L.items[k].on && L.items[k].size == "T" {
        L.items[k].size = "L"; L.items[k].w = SIZES["L"]!.w; L.items[k].h = SIZES["L"]!.h
      }
      spot = slotFor(L.items, id, L.items[i].w, L.items[i].h)
    }
    if let spot {
      L.items[i].col = spot.col; L.items[i].row = spot.row
      L.items[i].hc = spot.col; L.items[i].hr = spot.row
    }
    L.items[i].pri = nextPri(L)
  }
  return normalize(L.json)
}

/** 再加一个同种的组件（只有 multi 的能加）：新 id 是「种类-数字」，放进一屏里的空位 */
func addInstance(_ layout: Any?, _ type: String) -> (layout: Layout, id: String?) {
  var L = normalize(layout)
  guard let def = widgetDef(type), def.multi else { return (L, nil) }
  var n = 2
  while L.items.contains(where: { $0.id == "\(type)-\(n)" }) { n += 1 }
  let id = "\(type)-\(n)"
  let d = dims(type, def.size)
  L.items.append(LayoutItem(id: id, type: type, on: false, col: 0, row: 0, hc: 0, hr: 0, pri: 0, size: d.size!, w: d.w, h: d.h, name: ""))
  return (toggle(L.json, id, true), id)
}

/** 去掉一个组件：加出来的那些直接删掉，每种的第一个只是收起（布局里还留着它的位置） */
func removeInstance(_ layout: Any?, _ id: String) -> Layout {
  var L = normalize(layout)
  if id == typeOf(id) { return toggle(L.json, id, false) }
  L.items.removeAll { $0.id == id }
  return normalize(L.json)
}

/** 首次引导里的四种身份 → 一份默认布局（左右两列各 4 行，中间留空） */
func presetLayout(_ persona: String) -> JSON {
  let cols: [(String, Int, Int, String)]
  switch persona {
  case "student": cols = [("clock", 0, 0, "M"), ("butler", 0, 1, "M"), ("todo", 0, 2, "L"), ("weather", 6, 0, "M"), ("calendar", 6, 1, "L"), ("countdown", 6, 3, "M")]
  case "work": cols = [("clock", 0, 0, "M"), ("butler", 0, 1, "M"), ("mail", 0, 2, "L"), ("weather", 6, 0, "M"), ("calendar", 6, 1, "L"), ("worldclock", 6, 3, "M")]
  case "invest": cols = [("clock", 0, 0, "M"), ("butler", 0, 1, "M"), ("market", 0, 2, "L"), ("weather", 6, 0, "M"), ("news", 6, 1, "L"), ("crypto", 6, 3, "M")]
  default: cols = [("clock", 0, 0, "M"), ("butler", 0, 1, "M"), ("weather", 6, 0, "M")]   // 极简
  }
  let on = cols.map { c -> JSON in ["id": c.0, "on": true, "col": c.1, "row": c.2, "size": c.3] }
  let off = WIDGETS.filter { w in !cols.contains { $0.0 == w.id } }.map { w -> JSON in ["id": w.id, "on": false, "col": 2, "row": 0, "size": w.size] }
  return normalize(["version": Grid.version, "items": on + off]).json
}

func rename(_ layout: Any?, _ id: String, _ name: String) -> Layout {
  var L = normalize(layout)
  if let i = L.items.firstIndex(where: { $0.id == id }) { L.items[i].name = name.head(20) }
  return L
}

/** 能看到的组件（开着的） */
func visible(_ layout: Any?) -> [LayoutItem] {
  normalize(layout).items.filter(\.on)
}

struct Metrics { let cellW: Double, rowH: Double, gap: Double }

/** 网格 → 像素。宽度按屏宽算；给了高度就让 4 行正好铺满，不给就是正方形 */
func metrics(_ areaW: Double, _ areaH: Double? = nil) -> Metrics {
  let raw = (areaW - Grid.gap * Double(Grid.cols + 1)) / Double(Grid.cols)
  let cellW = min(Grid.cellMax, max(Grid.cellMin, raw))
  let rowH = areaH.map { min(Grid.rowMax, max(Grid.rowMin, ($0 - Grid.gap * Double(Grid.rows + 1)) / Double(Grid.rows))) } ?? cellW
  return Metrics(cellW: cellW, rowH: rowH, gap: Grid.gap)
}

struct Rect: Equatable { let left: Double, top: Double, width: Double, height: Double }

func toRect(col: Int, row: Int, w: Int, h: Int, _ areaW: Double, _ areaH: Double? = nil) -> Rect {
  let m = metrics(areaW, areaH)
  return Rect(
    left: (m.gap + Double(col) * (m.cellW + m.gap)).rounded(),
    top: (m.gap + Double(row) * (m.rowH + m.gap)).rounded(),
    width: (Double(w) * m.cellW + Double(w - 1) * m.gap).rounded(),
    height: (Double(h) * m.rowH + Double(h - 1) * m.gap).rounded()
  )
}

/** 像素 → 最近的格（拖动松手时用） */
func fromPoint(_ left: Double, _ top: Double, _ areaW: Double, _ areaH: Double? = nil) -> (col: Int, row: Int) {
  let m = metrics(areaW, areaH)
  return (
    min(Grid.cols - 1, max(0, Int(((left - m.gap) / (m.cellW + m.gap)).rounded()))),
    max(0, Int(((top - m.gap) / (m.rowH + m.gap)).rounded()))
  )
}
