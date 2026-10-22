// 市场页（原来的「市场」和「股票」合并成一页）：一张表同时放行情和你自己填的计划（买入价、卖出价、观察）；
// 量化系统的全部内容（统计、风控、持仓、观察池、选股候选、日报）折叠在最下面。
// 只做展示和提醒，不做买卖、不给建议；买入价 / 卖出价 / 观察都是你自己填的。
import SwiftUI

/** 输入框：回车或离开时才保存（行情每几秒刷新一次，不能边打字边被冲掉） */
struct CommitField: View {
  @Environment(\.pal) var pal
  let placeholder: String
  let value: String
  var width: CGFloat = 80
  var numeric = true
  let commit: (String) -> Void
  @State private var text = ""
  @FocusState private var focused: Bool

  var body: some View {
    TextField(placeholder, text: $text)
      .textFieldStyle(.plain).font(numeric ? Font2.num(12.5) : Font2.ui(12.5)).foregroundStyle(pal.text)
      .multilineTextAlignment(numeric ? .trailing : .leading)
      .padding(.horizontal, 7).padding(.vertical, 3)
      .background(RoundedRectangle(cornerRadius: 6).fill(focused ? pal.fill2 : pal.fill))
      .frame(width: width)
      .focused($focused)
      .onAppear { text = value }
      .onChange(of: value) { _, v in if !focused { text = v } }
      .onSubmit { commit(text) }
      .onChange(of: focused) { _, f in if !f && text != value { commit(text) } }
  }
}

struct PageHead<Trailing: View>: View {
  @Environment(\.pal) var pal
  let title: String
  var sub = ""
  @ViewBuilder var trailing: () -> Trailing
  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 10) {
      Text(title).font(Font2.ui(22, .semibold)).foregroundStyle(pal.text)
      Text(sub).font(Font2.ui(12.5)).foregroundStyle(pal.text3).lineLimit(1)
      Spacer()
      trailing()
    }
  }
}

struct Note: View {
  @Environment(\.pal) var pal
  let text: String
  var body: some View { Text(text).font(Font2.ui(11.5)).foregroundStyle(pal.text3).lineSpacing(3).fixedSize(horizontal: false, vertical: true) }
}

struct Panel<C: View>: View {
  @Environment(\.pal) var pal
  @ViewBuilder var content: () -> C
  var body: some View {
    VStack(alignment: .leading, spacing: 0) { content() }
      .padding(14).frame(maxWidth: .infinity, alignment: .leading)
      .background(RoundedRectangle(cornerRadius: 14).fill(pal.fill))
  }
}

struct MarketPage: View {
  @Environment(\.pal) var pal
  @ObservedObject var model: DeskModel
  @State private var add = ""
  @State private var quantOpen = false
  @State private var strat = "全部"

  var body: some View {
    let store = model.store
    let colors = store.colors
    let mono = colors != "rup" && colors != "gup"
    let watch = store.watch
    let budget = store.acctSize > 0 ? store.acctSize * store.maxPerPct / 100 : 0
    VStack(alignment: .leading, spacing: 14) {
      PageHead(title: L("市场"), sub: L("%@ 个品种 · 新浪公开行情，延迟数据，只做展示", "\(watch.count)")) {
        TextField(L("加自选：600519、00700、AAPL、腾讯"), text: $add).textFieldStyle(.plain).font(Font2.ui(13))
          .padding(.horizontal, 12).padding(.vertical, 6).background(Capsule().fill(pal.fill)).frame(width: 260).onSubmit(addSymbol)
        Button(L("添加"), action: addSymbol).buttonStyle(PillButton())
      }
      Panel {
        SwiftUI.Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 0) {
          GridRow {
            ForEach(["名称", "现价", "涨跌", "最高 / 最低", "状态", "买入价", "卖出价", "位置", "观察", ""], id: \.self) { h in
              Text(L(h)).font(Font2.ui(11.5, .medium)).foregroundStyle(pal.text3)
            }
          }.padding(.bottom, 8)
          ForEach(Array(watch.enumerated()), id: \.element) { i, key in
            let q = model.quotes[key]
            let plan = Plans.norm(store.plans[key])
            let ds = Plans.distanceText(plan, q?.price)
            let shares = budget > 0 && plan.buy != nil ? Int(budget / plan.buy!) : 0
            GridRow {
              Button { model.symbolOpen = key } label: {
                HStack(spacing: 5) {
                  Text(q?.name ?? key).font(Font2.ui(13, .medium)).foregroundStyle(pal.text)
                  Text(q?.code ?? Market.displayCode(key)).font(Font2.num(10.5)).foregroundStyle(pal.text3)
                  Text(L(q?.index == true ? "指数" : ["cn": "A 股", "hk": "港股", "us": "美股"][q?.market ?? ""] ?? "")).font(Font2.ui(10.5)).foregroundStyle(pal.text3)
                }
              }.buttonStyle(.plain)
              Text(F.price(q?.price)).font(Font2.num(13)).foregroundStyle(pal.text).gridColumnAlignment(.trailing)
              Text(mono ? F.pctMono(q?.pct) : F.pct(q?.pct)).font(Font2.num(12.5, .semibold)).foregroundStyle(pal.change(q?.pct, colors: colors)).gridColumnAlignment(.trailing)
              Text(q?.high != nil ? "\(F.price(q?.high)) / \(F.price(q?.low))" : "—").font(Font2.num(11.5)).foregroundStyle(pal.text2)
              Text(q.map { L(F.statusText($0.status, $0.market)) } ?? L("加载中")).font(Font2.ui(11)).foregroundStyle(pal.text3)
              if q?.index == true {
                // 指数不能买卖，不给填买入价 / 卖出价；「观察」还可以写
                Text("—").foregroundStyle(pal.text3); Text("—").foregroundStyle(pal.text3); Text("—").foregroundStyle(pal.text3)
              } else {
                CommitField(placeholder: "—", value: plan.buy.map(jsNum) ?? "") { setPlan(key, "buy", $0) }
                CommitField(placeholder: "—", value: plan.sell.map(jsNum) ?? "") { setPlan(key, "sell", $0) }
                VStack(alignment: .leading, spacing: 1) {
                  Text(ds.isEmpty ? "—" : ds).font(Font2.ui(11.5, ds.test("已低于|已高于") ? .semibold : .regular)).foregroundStyle(ds.test("已低于|已高于") ? pal.accent : pal.text2)
                  if shares > 0 { Text(L("上限≈%@ 股", "\(shares)")).font(Font2.ui(10.5)).foregroundStyle(pal.text3) }
                }
              }
              CommitField(placeholder: L("为什么看它"), value: plan.note, width: 150, numeric: false) { setPlan(key, "note", $0) }
              HStack(spacing: 4) {
                Button("↑") { moveWatch(i, -1) }.buttonStyle(MiniButton()).disabled(i == 0)
                Button("↓") { moveWatch(i, 1) }.buttonStyle(MiniButton()).disabled(i == watch.count - 1)
                Button(L("移除")) { removeWatch(key) }.buttonStyle(MiniButton())
              }
            }
            .frame(height: 38)
            .overlay(alignment: .top) { Rectangle().fill(pal.line).frame(height: 0.5) }
          }
        }
        if watch.isEmpty { Text(L("自选是空的，上面加一个")).font(Font2.ui(12.5)).foregroundStyle(pal.text3).padding(.top, 8) }
      }
      HStack(spacing: 8) {
        Text(L("涨跌幅超过")).foregroundStyle(pal.text2)
        CommitField(placeholder: "3", value: jsNum(store.alertPct), width: 50) { model.store.set(["alertPct": max(0, Double($0) ?? 0)]) }
        Text(L("% 时发系统通知（每个品种每天最多一次；填 0 关闭） · 账户")).foregroundStyle(pal.text2)
        CommitField(placeholder: "0", value: store.acctSize > 0 ? jsNum(store.acctSize) : "", width: 90) { model.store.set(["acctSize": max(0, Double($0) ?? 0)]) }
        Text(L("单票上限")).foregroundStyle(pal.text2)
        CommitField(placeholder: "20", value: jsNum(store.maxPerPct), width: 50) { model.store.set(["maxPerPct": min(100, max(1, Double($0) ?? 20))]) }
        Text("%").foregroundStyle(pal.text2)
        if budget > 0 { Text(L("· 每只最多 %@", F.money(budget, 0))).foregroundStyle(pal.text3) }
      }.font(Font2.ui(12))
      Note(text: L("主页显示能放下的前几个；有市场开盘时每 5 秒刷新，都收盘时每分钟刷新；港股延迟约 15 分钟。点名称看详情和 K 线。提醒只是告诉你行情变化，不代表任何买卖建议；买入价、卖出价、观察都是你自己填的。"))
      DisclosureGroup(isExpanded: $quantOpen) { QuantFold(model: model, strat: $strat).padding(.top, 10) } label: {
        Text(quantSummary).font(Font2.ui(14, .semibold)).foregroundStyle(pal.text)
      }
      .padding(.top, 6)
    }
  }

  private var quantSummary: String {
    guard let q = model.quant else { return L("量化账户 · 加载中") }
    guard q.ok else { return L("量化账户 · 没读到数据") }
    return L(q.running == true ? "量化账户 · 运行中 · 总资产 %@" : "量化账户 · 已停机 · 总资产 %@", F.money(q.account?.total, 0))
  }

  private func addSymbol() {
    let v = add.trimmed()
    guard !v.isEmpty else { return }
    Task {
      do { model.toast = model.addWatch(try await model.resolveSymbol(v)); add = "" } catch { model.toast = error.localizedDescription }
    }
  }

  private func setPlan(_ key: String, _ field: String, _ v: String) {
    var all = model.store.plans
    var p = all[key] as? JSON ?? [:]
    if field == "note" { p["note"] = String(v.prefix(80)) }
    else if let n = Double(v.trimmed()), n > 0 { p[field] = n } else { p[field] = NSNull() }
    all[key] = p
    model.store.set(["plans": all])
    model.toast = field == "note" ? L("观察已记下") : L("已保存")
  }

  private func moveWatch(_ i: Int, _ d: Int) {
    var w = model.store.watch
    let j = i + d
    guard j >= 0, j < w.count else { return }
    w.swapAt(i, j)
    model.store.set(["watch": w])
  }

  private func removeWatch(_ key: String) {
    var plans = model.store.plans
    plans[key] = nil
    model.store.set(["watch": model.store.watch.filter { $0 != key }, "plans": plans])
    model.toast = L("已移除")
  }
}

/** 量化账户：只读量化系统写出的文件，不改、不启动、不下单 */
struct QuantFold: View {
  @Environment(\.pal) var pal
  @ObservedObject var model: DeskModel
  @Binding var strat: String

  var body: some View {
    if let q = model.quant, q.ok {
      let a = q.account
      VStack(alignment: .leading, spacing: 14) {
        HStack(spacing: 10) {
          Text(q.running == true ? L("量化系统运行中") : L("量化系统已停机")).font(Font2.ui(11.5, .medium)).foregroundStyle(q.running == true ? pal.green : pal.text2)
            .padding(.horizontal, 8).padding(.vertical, 3).background(Capsule().fill(pal.fill))
          Text(L("数据时间 %@（原系统本机时间）", q.updatedAt ?? "—")).font(Font2.ui(12)).foregroundStyle(pal.text3)
          Spacer()
          if q.running == true { Button(L("打开原看板 ↗")) { model.openURL("http://127.0.0.1:8765") }.buttonStyle(PillButton()) }
          if let r = q.reports.first { Button(L("最新日报 %@", String(r.date.suffix(5)))) { NSWorkspace.shared.open(URL(fileURLWithPath: r.path)) }.buttonStyle(PillButton()) }
        }
        if q.running != true {
          banner(L("⏸ 量化系统现在没有运行，推送、30 秒刷新、收盘日报都停了。下面是它停机前最后一次写出的数据，价格不是最新的。"), pal.orange)
        }
        if let r = q.risk, r.status == "exit" {
          banner(L("⚠︎ 按你给量化系统定的规则，账户已进入清仓警戒：从最高点回撤 %@%%，超过了 %@%% 的清仓线。系统只提示、不下单，要不要操作、要不要改规则，由你自己决定。", r.drawdown.map(jsNum) ?? "—", r.exitLine.map(jsNum) ?? "—"), pal.red)
        }
        HStack(spacing: 12) {
          stat(L("总资产"), F.money(a?.total), L("初始资金 %@", F.money(a?.initial)))
          stat(L("累计盈亏"), F.signed(a?.pnl), F.pct(a?.pnlPct))
          stat(L("今日盈亏"), F.signed(a?.dayPnl), L("按（现价 − 昨收）× 股数"))
          stat(L("仓位"), "\(a?.posRatio.map(jsNum) ?? "—")%", L("市值 %@ · 现金 %@", F.money(a?.mv, 0), F.money(a?.cash, 0)) + myShare(a?.mv))
        }
        if let r = q.risk {
          VStack(alignment: .leading, spacing: 8) {
            HStack {
              Text(L("风控")).font(Font2.ui(14, .semibold)).foregroundStyle(pal.text)
              Text(F.riskText(r.status)).font(Font2.ui(11, .medium)).foregroundStyle(r.status == "normal" ? pal.text2 : pal.orange).padding(.horizontal, 7).padding(.vertical, 2).background(Capsule().fill(pal.fill2))
              Spacer()
              Text(L("最高资产 %@ · 单票止损线 %@%%", F.money(r.peak), r.stopLoss.map(jsNum) ?? "—")).font(Font2.ui(12)).foregroundStyle(pal.text3)
            }
            Gauge(risk: r)
          }
        }
        Text(L("持仓 · %@ 只", "\(q.positions.count)")).font(Font2.ui(14, .semibold)).foregroundStyle(pal.text)
        ForEach(Array(q.positions.enumerated()), id: \.offset) { _, p in PositionCard(model: model, p: effective(p)) }
        if !q.watchlist.isEmpty {
          Text(L("观察池 · %@ 只（量化系统筛的，只读；点「加自选」就能在上面填价）", "\(q.watchlist.count)")).font(Font2.ui(14, .semibold)).foregroundStyle(pal.text)
          pickTable(q.watchlist, scan: false)
        }
        if let s = q.scan {
          HStack {
            Text(L("选股候选")).font(Font2.ui(14, .semibold)).foregroundStyle(pal.text)
            Text("\(s.mode) · 市场判断：\(s.regime.isEmpty ? "—" : s.regime) · \(s.universe.map(jsNum) ?? "—") → \(s.prefiltered.map(jsNum) ?? "—") → \(s.qualified.map(jsNum) ?? "—") 只").font(Font2.ui(12)).foregroundStyle(pal.text3)
            Spacer()
            Picker("", selection: $strat) { ForEach(["全部", "GARP", "动量"], id: \.self) { Text(L($0)).tag($0) } }.pickerStyle(.segmented).frame(width: 180).labelsHidden()
          }
          pickTable(s.candidates.filter { strat == "全部" || $0.strategy == strat || $0.strategy == "双策略" }, scan: true)
          Note(text: L("候选是量化系统按你定的选股规则筛出来的名单，不是推荐。"))
        }
        Text(L("收盘日报")).font(Font2.ui(14, .semibold)).foregroundStyle(pal.text)
        HStack(spacing: 6) {
          ForEach(Array(q.reports.prefix(10).enumerated()), id: \.offset) { _, r in
            Button(r.date) { NSWorkspace.shared.open(URL(fileURLWithPath: r.path)) }.buttonStyle(MiniButton())
          }
          if q.reports.isEmpty { Text(L("没有日报")).font(Font2.ui(12)).foregroundStyle(pal.text3) }
        }
        Note(text: L("数据来自 %@，这里只读不改。和原看板相比修正了两处显示口径：今日盈亏按（现价 − 昨收）× 股数计算；仓位按市值 ÷ 总资产计算。", q.dir))
      }
    } else {
      Text(model.quant?.error.map { $0 + "\n" + L("可以在「设置」里改量化系统所在的文件夹。") } ?? L("加载中…")).font(Font2.ui(12.5)).foregroundStyle(pal.orange)
    }
  }

  private func banner(_ t: String, _ c: Color) -> some View {
    Text(t).font(Font2.ui(12.5)).foregroundStyle(pal.text).padding(12).frame(maxWidth: .infinity, alignment: .leading)
      .background(RoundedRectangle(cornerRadius: 10).fill(c.opacity(0.16)))
  }

  private func stat(_ label: String, _ value: String, _ sub: String) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(label).font(Font2.ui(11.5)).foregroundStyle(pal.text3)
      Text(value).font(Font2.round(20, .medium)).foregroundStyle(pal.text)
      Text(sub).font(Font2.ui(11)).foregroundStyle(pal.text3).lineLimit(2)
    }
    .padding(12).frame(maxWidth: .infinity, alignment: .leading).background(RoundedRectangle(cornerRadius: 12).fill(pal.fill))
  }

  /** 第二套口径：按你自己填的账户金额算占比，只显示，不替代量化系统的口径 */
  private func myShare(_ mv: Double?) -> String {
    guard let s = Plans.shareOf(mv, model.store.acctSize) else { return "" }
    return "\n" + L("按你填的 %@ 算 %@%%", F.money(model.store.acctSize, 0), jsNum(s))
  }

  /** 手改持仓：只覆盖这一张卡片的股数 / 成本，市值和盈亏按现价重算 */
  private func effective(_ p: QuantPosition) -> (QuantPosition, Bool) {
    guard let e = (model.store.data["posEdits"] as? JSON)?[p.code] as? JSON else { return (p, false) }
    var x = p
    let shares = num(e["shares"]) ?? p.shares ?? 0, cost = num(e["cost"]) ?? p.cost ?? 0, price = p.price ?? 0
    x.shares = shares; x.cost = cost
    x.mv = round2(shares * price); x.pnl = round2((price - cost) * shares)
    x.pnlPct = cost != 0 ? round2((price - cost) / cost * 100) : nil
    return (x, true)
  }

  private func pickTable(_ list: [QuantPick], scan: Bool) -> some View {
    Panel {
      SwiftUI.Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
        GridRow {
          ForEach(scan ? ["名称", "策略", "板块", "现价", "涨跌幅", "PE", "PEG", "ROE", "营收增速", "利润增速", ""] : ["名称", "现价", "涨跌幅", "MA10", "MA20", "趋势", "原系统信号", ""], id: \.self) {
            Text(L($0)).font(Font2.ui(11.5, .medium)).foregroundStyle(pal.text3)
          }
        }
        ForEach(Array(list.enumerated()), id: \.offset) { _, w in
          GridRow {
            HStack(spacing: 5) { Text(w.name).foregroundStyle(pal.text); Text(w.code).font(Font2.num(10.5)).foregroundStyle(pal.text3) }
            if scan {
              Text(w.strategy).foregroundStyle(pal.text2)
              Text(w.sector + (w.heat.isEmpty ? "" : " " + w.heat)).foregroundStyle(pal.text2).lineLimit(1)
            }
            Text(F.price(w.price)).font(Font2.num(12.5))
            Text(F.pct(w.pct)).font(Font2.num(12.5)).foregroundStyle(pal.change(w.pct, colors: model.store.colors))
            if scan {
              Text(w.pe.map(jsNum) ?? "—"); Text(w.peg.map(jsNum) ?? "—"); Text(w.roe.map { jsNum($0) + "%" } ?? "—")
              Text(w.revGrow.map { jsNum($0) + "%" } ?? "—"); Text(w.profitGrow.map { jsNum($0) + "%" } ?? "—")
            } else {
              Text(w.ma10.map(jsNum) ?? "—"); Text(w.ma20.map(jsNum) ?? "—")
              Text(L(["up": "上升", "down": "下降", "flat": "震荡"][w.trend] ?? "—"))
              Text(L(["hold": "持有", "enter": "入场", "add": "加仓", "exit": "离场"][w.signal] ?? (w.signal.isEmpty ? "—" : w.signal)))
            }
            Button(L("加自选")) {
              Task { do { model.toast = model.addWatch(try await model.resolveSymbol(w.code)) + L("，上面可以填买入价了") } catch { model.toast = error.localizedDescription } }
            }.buttonStyle(MiniButton())
          }
          .font(Font2.ui(12.5)).foregroundStyle(pal.text2)
        }
      }
    }
  }
}

struct Gauge: View {
  @Environment(\.pal) var pal
  let risk: QuantRisk
  var body: some View {
    GeometryReader { g in
      let pos = { (v: Double?) in CGFloat(min(100, max(0, abs(v ?? 0) / 30 * 100))) / 100 * g.size.width }
      ZStack(alignment: .leading) {
        Capsule().fill(LinearGradient(colors: [pal.green.opacity(0.5), pal.orange.opacity(0.6), pal.red.opacity(0.7)], startPoint: .leading, endPoint: .trailing)).frame(height: 6).offset(y: 10)
        mark(pos(risk.halfLine), "降半仓 \(risk.halfLine.map(jsNum) ?? "—")%")
        mark(pos(risk.exitLine), "清仓 \(risk.exitLine.map(jsNum) ?? "—")%")
        VStack(spacing: 2) {
          Text("\(risk.drawdown.map(jsNum) ?? "—")%").font(Font2.num(11.5, .semibold)).foregroundStyle(pal.text)
          Circle().fill(pal.text).frame(width: 10, height: 10)
        }.offset(x: pos(risk.drawdown) - 14, y: -10)
      }
    }.frame(height: 46).padding(.horizontal, 20)
  }
  private func mark(_ x: CGFloat, _ t: String) -> some View {
    VStack(spacing: 2) {
      Rectangle().fill(pal.text2).frame(width: 1, height: 14)
      Text(t).font(Font2.ui(10.5)).foregroundStyle(pal.text3).fixedSize()
    }.offset(x: x, y: 6)
  }
}

struct PositionCard: View {
  @Environment(\.pal) var pal
  @ObservedObject var model: DeskModel
  let p: (QuantPosition, Bool)

  var body: some View {
    let (x, edited) = p
    HStack(alignment: .top, spacing: 18) {
      VStack(alignment: .leading, spacing: 8) {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
          Text(x.name).font(Font2.ui(16, .semibold)).foregroundStyle(pal.text)
          Text(x.code).font(Font2.num(12)).foregroundStyle(pal.text3)
        }
        HStack(alignment: .firstTextBaseline, spacing: 8) {
          Text(F.price(x.price)).font(Font2.round(28, .medium)).foregroundStyle(pal.text)
          Text(F.pct(x.pct)).font(Font2.num(12.5, .semibold)).foregroundStyle(pal.change(x.pct, colors: model.store.colors))
        }
        SwiftUI.Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 4) {
          row(L("持股"), L("%@ 股", x.shares.map(jsNum) ?? "—")); row(L("成本"), x.cost.map(jsNum) ?? "—"); row(L("市值"), F.money(x.mv))
          row(L("浮动盈亏"), "\(F.signed(x.pnl)) (\(F.pct(x.pnlPct)))"); row(L("今日盈亏"), F.signed(x.dayPnl))
          row("MA10 / MA20", "\(x.ma10.map(jsNum) ?? "—") / \(x.ma20.map(jsNum) ?? "—")")
          row(L("距持仓最高价"), L("%@（高 %@）", x.trailPct.map { jsNum($0) + "%" } ?? "—", x.maxPrice.map(jsNum) ?? "—"))
          if let s = Plans.shareOf(x.mv, model.store.acctSize) { row(L("占 %@ 的", F.money(model.store.acctSize, 0)), "\(jsNum(s))%") }
        }
        HStack(spacing: 6) {
          Text(L("手改")).font(Font2.ui(11.5)).foregroundStyle(pal.text3)
          Text(L("股数")).font(Font2.ui(11.5)).foregroundStyle(pal.text2)
          CommitField(placeholder: "", value: x.shares.map(jsNum) ?? "", width: 70) { edit(x.code, "shares", $0) }
          Text(L("成本")).font(Font2.ui(11.5)).foregroundStyle(pal.text2)
          CommitField(placeholder: "", value: x.cost.map(jsNum) ?? "", width: 70) { edit(x.code, "cost", $0) }
          if edited { Button(L("恢复原值")) { reset(x.code) }.buttonStyle(MiniButton()) }
        }
        Text(L("原系统今日信号：") + (x.signal.isEmpty ? "—" : x.signal) + "\n" + L("做 T：") + (x.tMsg.isEmpty ? "—" : x.tMsg)).font(Font2.ui(11.5)).foregroundStyle(pal.text3)
      }
      .frame(width: 300, alignment: .leading)
      if let k = x.kline { KLineView(k: k, cost: x.cost).frame(height: 230) } else { Text(L("没有 K 线")).font(Font2.ui(12)).foregroundStyle(pal.text3) }
    }
    .padding(16).background(RoundedRectangle(cornerRadius: 14).fill(pal.fill))
  }

  private func row(_ a: String, _ b: String) -> some View {
    GridRow { Text(a).foregroundStyle(pal.text3); Text(b).foregroundStyle(pal.text2) }.font(Font2.ui(12))
  }

  private func edit(_ code: String, _ field: String, _ v: String) {
    var all = model.store.data["posEdits"] as? JSON ?? [:]
    var one = all[code] as? JSON ?? [:]
    if let n = Double(v.trimmed()), n >= 0 { one[field] = n } else { one[field] = nil }
    all[code] = one.isEmpty ? nil : one
    model.store.set(["posEdits": all])
    model.toast = one.isEmpty ? L("已恢复量化系统的数字") : L("已按你填的数字重算")
  }

  private func reset(_ code: String) {
    var all = model.store.data["posEdits"] as? JSON ?? [:]
    all[code] = nil
    model.store.set(["posEdits": all])
    model.toast = L("已恢复量化系统读到的数字")
  }
}

/** K 线：蜡烛 + MA10 / MA20 + 成本线（虚线）+ 右侧价格 */
struct KLineView: View {
  @Environment(\.pal) var pal
  let k: KLine
  var cost: Double? = nil
  var body: some View {
    Canvas { ctx, size in
      let n = k.close.count
      guard n > 0 else { return }
      let padL = 6.0, padR = 48.0, padT = 10.0, padB = 18.0
      var vals = k.high + k.low + k.ma10.compactMap { $0 } + k.ma20.compactMap { $0 }
      if let cost { vals.append(cost) }
      let hi = vals.max()!, lo = vals.min()!, span = max(hi - lo, 0.0001)
      let W = Double(size.width), H = Double(size.height)
      let y = { (v: Double) in CGFloat(padT + (1 - (v - lo) / span) * (H - padT - padB)) }
      let step = (W - padL - padR) / Double(n)
      let x = { (i: Int) in CGFloat(padL + step * Double(i) + step / 2) }
      let bw = CGFloat(max(1.5, step * 0.62))
      for i in 0...3 {
        let v = lo + span * Double(i) / 3
        var p = Path(); p.move(to: CGPoint(x: padL, y: y(v))); p.addLine(to: CGPoint(x: W - padR, y: y(v)))
        ctx.stroke(p, with: .color(pal.line), lineWidth: 0.5)
        ctx.draw(Text(String(format: "%.2f", v)).font(Font2.num(10)).foregroundColor(pal.text3), at: CGPoint(x: W - padR + 24, y: y(v)))
      }
      for i in 0..<n {
        let up = k.close[i] >= k.open[i]
        let c = up ? pal.text : pal.text2
        var wick = Path(); wick.move(to: CGPoint(x: x(i), y: y(k.high[i]))); wick.addLine(to: CGPoint(x: x(i), y: y(k.low[i])))
        ctx.stroke(wick, with: .color(c), lineWidth: 1)
        let top = y(max(k.open[i], k.close[i])), bot = y(min(k.open[i], k.close[i]))
        let r = CGRect(x: x(i) - bw / 2, y: top, width: bw, height: max(1, bot - top))
        if up { ctx.stroke(Path(r), with: .color(c), lineWidth: 1) } else { ctx.fill(Path(r), with: .color(c)) }
      }
      for (arr, color) in [(k.ma10, Color(hex: "#f0d2a0")), (k.ma20, Color(hex: "#9b8cff"))] {
        var p = Path(); var started = false
        for (i, v) in arr.enumerated() { guard let v else { continue }; if started { p.addLine(to: CGPoint(x: x(i), y: y(v))) } else { p.move(to: CGPoint(x: x(i), y: y(v))); started = true } }
        ctx.stroke(p, with: .color(color), lineWidth: 1.4)
      }
      if let cost {
        var p = Path(); p.move(to: CGPoint(x: padL, y: y(cost))); p.addLine(to: CGPoint(x: W - padR, y: y(cost)))
        ctx.stroke(p, with: .color(pal.text2), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
        ctx.draw(Text(L("成本 %@", jsNum(cost))).font(Font2.ui(10)).foregroundColor(pal.text2), at: CGPoint(x: padL + 30, y: y(cost) - 8))
      }
      if let first = k.dates.first, let last = k.dates.last {
        ctx.draw(Text(String(first.suffix(5))).font(Font2.num(10)).foregroundColor(pal.text3), at: CGPoint(x: padL + 16, y: H - 6))
        ctx.draw(Text(String(last.suffix(5))).font(Font2.num(10)).foregroundColor(pal.text3), at: CGPoint(x: W - padR - 16, y: H - 6))
      }
    }
  }
}

/** 品种详情（A 股带日 K 线）+ 价格到达提醒 + 网上链接 */
struct SymbolPanel: View {
  @Environment(\.pal) var pal
  @ObservedObject var model: DeskModel
  let key: String
  @State private var kline: KLine?
  @State private var loaded = false

  var body: some View {
    let q = model.quotes[key] ?? Quote(key: key, code: Market.displayCode(key), market: Market.marketOf(key), name: key)
    let pa = model.store.priceAlerts[key] as? JSON ?? [:]
    SidePanel(close: { model.symbolOpen = nil }) {
      VStack(alignment: .leading, spacing: 12) {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
          Text(q.name).font(Font2.ui(20, .semibold)).foregroundStyle(pal.text)
          Text(q.code).font(Font2.num(13)).foregroundStyle(pal.text3)
        }
        Text("\(L(q.index ? "指数" : ["cn": "A 股", "hk": "港股", "us": "美股"][q.market] ?? "")) · \(F.statusText(q.status, q.market)) · " + L("数据时间 %@", F.rel(q.ts))).font(Font2.ui(12)).foregroundStyle(pal.text3)
        HStack(alignment: .firstTextBaseline, spacing: 10) {
          Text(F.price(q.price)).font(Font2.round(34, .medium)).foregroundStyle(pal.text)
          Text("\(F.signed(q.chg, 3))　\(F.pct(q.pct))").font(Font2.num(13, .semibold)).foregroundStyle(pal.change(q.pct, colors: model.store.colors))
        }
        SwiftUI.Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 6) {
          GridRow { kv(L("今开"), F.price(q.open)); kv(L("昨收"), F.price(q.prev)) }
          GridRow { kv(L("最高"), F.price(q.high)); kv(L("最低"), F.price(q.low)) }
        }
        Text(L("走势")).font(Font2.ui(13, .semibold)).foregroundStyle(pal.text).padding(.top, 6)
        if q.market != "cn" {
          Text(L("港股、美股暂时只显示报价；K 线可以在浏览器里看")).font(Font2.ui(12)).foregroundStyle(pal.text3)
        } else if let kline, !kline.isEmpty {
          KLineView(k: kline).frame(height: 220)
          Text(L("MA10 浅金 · MA20 浅紫 · 近 %@ 个交易日", "\(kline.close.count)")).font(Font2.ui(11)).foregroundStyle(pal.text3)
        } else {
          Text(loaded ? L("K 线加载失败") : L("K 线加载中…")).font(Font2.ui(12)).foregroundStyle(pal.text3)
        }
        Text(L("价格到达提醒")).font(Font2.ui(13, .semibold)).foregroundStyle(pal.text).padding(.top, 6)
        HStack(spacing: 8) {
          Text(L("高于")).foregroundStyle(pal.text2)
          CommitField(placeholder: "", value: num(pa["above"]).map(jsNum) ?? "", width: 90) { setAlert("above", $0) }
          Text(L("低于")).foregroundStyle(pal.text2)
          CommitField(placeholder: "", value: num(pa["below"]).map(jsNum) ?? "", width: 90) { setAlert("below", $0) }
        }.font(Font2.ui(12.5))
        Note(text: L("到价后发一次系统通知（每天最多一次）。只是提醒，不是买卖建议。"))
        Text(L("在网上看")).font(Font2.ui(13, .semibold)).foregroundStyle(pal.text).padding(.top, 6)
        HStack(spacing: 6) { ForEach(links(q), id: \.0) { n, u in Button(L(n) + " ↗") { model.openURL(u) }.buttonStyle(MiniButton()) } }
      }
    }
    .task(id: key) { kline = await Fetch.daily(key); loaded = true }
  }

  private func kv(_ a: String, _ b: String) -> some View {
    HStack { Text(a).foregroundStyle(pal.text3); Spacer(); Text(b).font(Font2.num(12.5)).foregroundStyle(pal.text) }.font(Font2.ui(12.5)).frame(width: 190)
  }

  private func setAlert(_ field: String, _ v: String) {
    var all = model.store.priceAlerts
    var one = all[key] as? JSON ?? [:]
    if let n = Double(v.trimmed()), n > 0 { one[field] = n } else { one[field] = nil }
    all[key] = one.isEmpty ? nil : one
    model.store.set(["priceAlerts": all])
    model.toast = L("已保存提醒")
  }

  private func links(_ q: Quote) -> [(String, String)] {
    switch q.market {
    case "cn": return [("新浪财经", "https://finance.sina.com.cn/realstock/company/\(q.key)/nc.shtml"), ("东方财富", "https://quote.eastmoney.com/\(q.key).html")]
    case "hk": return [("新浪港股", "https://stock.finance.sina.com.cn/hkstock/quotes/\(q.code).html"), ("TradingView", "https://www.tradingview.com/symbols/HKEX-\(Int(q.code).map(String.init) ?? q.code)/")]
    default: return [("新浪美股", "https://stock.finance.sina.com.cn/usstock/quotes/\(q.code.lowercased()).html"), ("TradingView", "https://www.tradingview.com/symbols/\(q.code)/")]
    }
  }
}

/** 新闻页：全部新闻，按分类筛选 */
struct NewsPage: View {
  @Environment(\.pal) var pal
  @ObservedObject var model: DeskModel
  @State private var tag = "全部"
  var body: some View {
    let n = model.news
    let items = (n?.items ?? []).filter { tag == "全部" || $0.tag == tag }
    VStack(alignment: .leading, spacing: 14) {
      PageHead(title: L("新闻"), sub: News.pick(model.store.newsSources).map(\.name).joined(separator: " · ") + (n.map { $0.at > 0 ? L(" · 更新于 ") + F.rel($0.at) : "" } ?? "")) {
        Picker("", selection: $tag) { ForEach(["全部", "财经", "科技", "国际", "大中华", "本地"], id: \.self) { Text(L($0)).tag($0) } }.pickerStyle(.segmented).frame(width: 360).labelsHidden()
        Button(L("刷新")) { model.kick("news") }.buttonStyle(PillButton())
      }
      if let e = n?.error { Text(L("更新失败：%@，显示的是之前的新闻", e)).font(Font2.ui(12.5)).foregroundStyle(pal.orange) }
      Panel {
        if items.isEmpty { Text(n == nil ? "加载中…" : "没有新闻").font(Font2.ui(12.5)).foregroundStyle(pal.text3) }
        ForEach(Array(items.enumerated()), id: \.offset) { i, x in
          Button { model.openURL(x.link) } label: {
            VStack(alignment: .leading, spacing: 4) {
              Text(x.title).font(Font2.ui(15, .medium)).foregroundStyle(pal.text).multilineTextAlignment(.leading)
              if !x.desc.isEmpty { Text(x.desc).font(Font2.ui(12.5)).foregroundStyle(pal.text2).lineSpacing(2).multilineTextAlignment(.leading) }
              Text("\(L(x.tag)) · \(x.source) · \(F.rel(x.ts)) · " + L("阅读原文 ↗")).font(Font2.ui(11)).foregroundStyle(pal.text3)
            }.padding(.vertical, 10).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
          }.buttonStyle(.plain)
          .overlay(alignment: .top) { if i > 0 { Rectangle().fill(pal.line).frame(height: 0.5) } }
        }
      }
    }
  }
}
