// 网格布局：三档、补齐、夹界、解重叠、拖动让位、自动复位、旧版迁移、像素换算（对应 test/layout.test.js）
import Foundation

private func item(_ L: Any?, _ id: String) -> LayoutItem { normalize(L).item(id)! }
private func ids(_ L: Any?) -> [String] { visible(L).map(\.id) }
private func noOverlap(_ L: Any?, line: Int = #line) {
  let on = normalize(L).items.filter(\.on)
  for i in on.indices { for j in on.indices where j > i {
    ok(!overlaps((on[i].col, on[i].row, on[i].w, on[i].h), (on[j].col, on[j].row, on[j].w, on[j].h)), "\(on[i].id) 和 \(on[j].id) 重叠了", line: line)
  } }
}
private func pos(_ L: Layout, _ id: String) -> [Int] { let i = L.item(id)!; return [i.col, i.row] }

private let FULL: JSON = ["version": Grid.version, "items": [
  ["id": "clock", "on": true, "col": 0, "row": 0, "size": "M"],
  ["id": "butler", "on": true, "col": 2, "row": 0, "size": "W"],
  ["id": "weather", "on": true, "col": 6, "row": 0, "size": "M"],
  ["id": "market", "on": true, "col": 0, "row": 1, "size": "T"],
  ["id": "calendar", "on": true, "col": 2, "row": 1, "size": "T"],
  ["id": "mail", "on": true, "col": 4, "row": 1, "size": "T"],
  ["id": "news", "on": true, "col": 6, "row": 1, "size": "T"],
] as [JSON]]

func layoutTests() {
  test("每个组件的默认档位都在它允许的档位里，且档位表里有定义") {
    for w in WIDGETS {
      ok(w.sizes.contains(w.size), w.id)
      for s in w.sizes { ok(SIZES[s] != nil, "\(w.id) 用了不存在的档位 \(s)") }
    }
  }

  test("默认布局合法、normalize 不改位置；中间留空，左右两列各自铺满 4 行") {
    let L = normalize(DEFAULT_LAYOUT)
    eq(L.items.count, WIDGETS.count)
    noOverlap(DEFAULT_LAYOUT)
    for d in DEFAULT_LAYOUT["items"] as! [JSON] {
      let got = L.item(d["id"] as! String)!
      eq(got.col, d["col"] as! Int); eq(got.row, d["row"] as! Int)
    }
    let cells = visible(DEFAULT_LAYOUT)
    for (lo, hi) in [(0, 1), (6, 7)] {
      let col = cells.filter { $0.col >= lo && $0.col + $0.w - 1 <= hi }
      eq(col.reduce(0) { $0 + $1.w * $1.h }, 2 * Grid.rows, "一列没有铺满 4 行")
    }
    ok(cells.allSatisfy { $0.col + $0.w <= 2 || $0.col >= 6 }, "中间 4 列必须留空")
    ok(!ids(DEFAULT_LAYOUT).contains("news"), "新闻默认关着")
  }

  test("空布局会补齐所有组件（存过布局后新出现的组件默认关着）") {
    let L = normalize(nil)
    eq(L.items.count, WIDGETS.count)
    eq(L.item("butler")!.on, true)
    let stored = normalize(["version": Grid.version, "items": [["id": "clock", "col": 0, "row": 0, "size": "M"]]])
    eq(stored.item("mail")!.on, false)
  }

  test("档位决定宽高；不允许的档位退回默认档") {
    eq([item(DEFAULT_LAYOUT, "market").w, item(DEFAULT_LAYOUT, "market").h], [2, 2])
    eq([item(DEFAULT_LAYOUT, "butler").w, item(DEFAULT_LAYOUT, "butler").h], [2, 1])
    eq(dims("calendar", "S").size, "L")
    eq(dims("not-a-widget", "S").size, nil)
    eq(dims("__proto__", "S").size, nil, "不能取到奇怪的东西")
  }

  test("越界的位置会被夹回网格内（按档位的宽度夹）") {
    let b = item(["version": Grid.version, "items": [["id": "butler", "col": 99, "row": -5, "size": "W"]]], "butler")
    eq(b.col, Grid.cols - 4); eq(b.row, 0)
  }

  test("两个组件撞在一起：被挤的就近让到一屏之内的空位") {
    let raw: JSON = ["version": Grid.version, "items": [
      ["id": "market", "col": 0, "row": 0, "size": "L", "pri": 1],
      ["id": "news", "col": 1, "row": 1, "size": "L"],
    ]]
    let L = normalize(raw)
    eq(pos(L, "market"), [0, 0])
    noOverlap(raw)
    let n = L.item("news")!
    ok(n.row + n.h <= Grid.rows && n.col + n.w <= Grid.cols, "不能掉到屏幕外面")
  }

  test("拖动撞到别人：被撞的就近让开；挪走之后被撞的自动回到原位") {
    let dragged = move(DEFAULT_LAYOUT, "weather", 0, 0)
    eq(pos(dragged, "weather"), [0, 0])
    noOverlap(dragged.json)
    let c = dragged.item("clock")!
    ok(!(c.col == 0 && c.row == 0), "时钟要让出位置")
    ok(c.row + c.h <= Grid.rows)
    let back = move(dragged.json, "weather", 6, 0)
    eq(pos(back, "clock"), [0, 0], "挤它的走了，时钟自动回到原位")
    noOverlap(back.json)
  }

  test("拖动不会拖出网格右边") {
    eq(move(DEFAULT_LAYOUT, "weather", 99, 0).item("weather")!.col, Grid.cols - 2)
  }

  test("换档：只能换成允许的档位") {
    let m = setSize(DEFAULT_LAYOUT, "market", "M").item("market")!
    eq([m.size, "\(m.w)", "\(m.h)"], ["M", "2", "1"])
    eq(setSize(DEFAULT_LAYOUT, "calendar", "S").item("calendar")!.size, "L")
    eq(setSize(DEFAULT_LAYOUT, "market", "XXL").item("market")!.size, "L")
  }

  test("换成更宽的档位：靠右的组件自动贴回网格内") {
    eq(setSize(DEFAULT_LAYOUT, "butler", "L").item("butler")!.w, 2)
    let L2 = setSize(move(DEFAULT_LAYOUT, "butler", 6, 0).json, "butler", "W")
    eq(L2.item("butler")!.col, Grid.cols - 4)
  }

  test("换档撞到别人：对方让位，自己不重叠") {
    noOverlap(setSize(DEFAULT_LAYOUT, "clock", "S").json)
    let wide = setSize(DEFAULT_LAYOUT, "butler", "W")
    noOverlap(wide.json)
    eq(wide.item("butler")!.w, 4)
  }

  test("关掉一个组件后不再可见，但布局里还留着") {
    let L = toggle(DEFAULT_LAYOUT, "market", false)
    ok(!ids(L.json).contains("market"))
    eq(L.item("market")!.on, false)
    ok(ids(toggle(L.json, "market", true).json).contains("market"))
  }

  test("放大挤到别人：别人就近让开且仍在屏幕里；缩回去之后全部自动复位") {
    let before = normalize(DEFAULT_LAYOUT).items.filter(\.on).map { "\($0.id)@\($0.col),\($0.row)" }
    let big = setSize(DEFAULT_LAYOUT, "butler", "L")
    noOverlap(big.json)
    for it in big.items where it.on { ok(it.row + it.h <= Grid.rows, "\(it.id) 被挤出屏幕了") }
    eq(big.item("butler")!.h, 2)
    let wide = setSize(big.json, "butler", "W")
    noOverlap(wide.json)
    let small = setSize(wide.json, "butler", "M")
    eq(small.items.filter(\.on).map { "\($0.id)@\($0.col),\($0.row)" }, before, "缩回去之后都回到原位")
  }

  test("用户最近动过的组件优先：别人不会把它的位置抢走") {
    let L = setSize(DEFAULT_LAYOUT, "butler", "L")
    let again = normalize(L.json)
    eq(pos(again, "butler") + [again.item("butler")!.h], pos(L, "butler") + [2])
    noOverlap(again.json)
  }

  test("一屏实在放不下时的兜底：不重叠") {
    var L = normalize(DEFAULT_LAYOUT)
    for id in ["news", "worldclock", "risk"] { L = toggle(L.json, id, true) }
    L = setSize(L.json, "news", "T")
    noOverlap(L.json)
  }

  test("桌面有空位时打开新组件：放进空位，不动别人") {
    let L = toggle(DEFAULT_LAYOUT, "news", true)
    let n = L.item("news")!
    ok(n.row + n.h <= Grid.rows && n.col + n.w <= Grid.cols)
    eq(L.item("butler")!.col, 0)
    eq(L.item("calendar")!.size, "L")
    noOverlap(L.json)
  }

  test("一屏已经铺满时打开新组件：把「高」收成「大」腾出一行") {
    let L = toggle(FULL, "worldclock", true)
    let b = L.item("worldclock")!
    eq(b.on, true)
    ok(b.row + b.h <= Grid.rows && b.col + b.w <= Grid.cols)
    eq(L.item("market")!.size, "L")
    noOverlap(L.json)
  }

  test("改名：截到 20 字") {
    eq(rename(DEFAULT_LAYOUT, "butler", "阿福").item("butler")!.name, "阿福")
    eq(rename(DEFAULT_LAYOUT, "butler", String(repeating: "一", count: 50)).item("butler")!.name.count, 20)
  }

  test("旧版布局：位置回到默认，但开关和名字保留") {
    let old: JSON = ["version": 2, "cols": 12, "items": [
      ["id": "clock", "on": true, "col": 0, "row": 0, "w": 4, "h": 3],
      ["id": "market", "on": false, "col": 0, "row": 7, "w": 4, "h": 4],
      ["id": "butler", "on": true, "col": 4, "row": 0, "w": 5, "h": 4, "name": "阿福"],
      ["id": "hint", "on": true, "col": 4, "row": 9, "w": 5, "h": 1],
    ] as [JSON]]
    let L = normalize(old)
    eq(L.item("market")!.on, false)
    eq(L.item("butler")!.name, "阿福")
    eq(L.item("butler")!.col, 0)
    eq(L.item("butler")!.size, "M")
    ok(L.item("hint") == nil)
    noOverlap(old)
    eq(normalize(["version": 3, "items": FULL["items"]!]).item("butler")!.col, 0)
  }

  test("像素换算：不给高度时是正方形；给了高度，4 行正好铺满") {
    for w in [900.0, 1100, 1440, 1800, 2560, 4000] {
      let m = metrics(w)
      eq(m.cellW, m.rowH)
      ok(m.cellW >= Grid.cellMin && m.cellW <= Grid.cellMax)
    }
    for (w, h) in [(1440.0, 780.0), (1752, 1050), (2400, 1300)] {
      let r = metrics(w, h).rowH
      ok(r >= Grid.rowMin && r <= Grid.rowMax)
      if r > Grid.rowMin && r < Grid.rowMax { ok(abs(Double(Grid.rows) * r + Double(Grid.rows + 1) * Grid.gap - h) < 1) }
    }
    let cellW = metrics(1800).cellW
    let r = toRect(col: 0, row: 0, w: 4, h: 2, 1800)
    eq(r.left, Grid.gap); eq(r.top, Grid.gap)
    eq(r.width, (4 * cellW + 3 * Grid.gap).rounded())
    eq(r.height, (2 * cellW + Grid.gap).rounded())
  }

  test("像素 → 格 往返一致") {
    for col in [0, 1, 4, 7] { for row in [0, 2, 5] {
      let r = toRect(col: col, row: row, w: 1, h: 1, 1800)
      let p = fromPoint(r.left, r.top, 1800)
      eq([p.col, p.row], [col, row])
    } }
  }

  test("传进来的是垃圾也不崩") {
    for bad: Any? in [nil, [:] as JSON, ["items": "x"] as JSON, ["items": [NSNull(), 1, [:] as JSON] as [Any]] as JSON] {
      eq(normalize(bad).items.count, WIDGETS.count)
    }
  }
}
