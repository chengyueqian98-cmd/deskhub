// 桌面小组件（第三版视觉：没有底色、没有卡片，用一条发丝线分隔）。桌面层和浮层共用。
// 列表装不下就少显示几行（整行收起，不画半行）——行数按格子高度算。
import SwiftUI

/** 一个格子里要知道的东西 */
struct Cell {
  let id: String
  let size: CGSize
  let sizeKey: String
  let interactive: Bool    // 浮层里可以点；桌面层收不到鼠标
}

// —— 标题行 ——
struct WHead<Trailing: View>: View {
  @Environment(\.pal) var pal
  var icon: String?
  let title: String
  var color: Color?
  var pulse: Pulse? = nil
  @ViewBuilder var trailing: () -> Trailing

  var body: some View {
    HStack(spacing: 6) {
      if let icon { Image(systemName: icon).font(.system(size: 11, weight: .semibold)).foregroundStyle(pal.text3) }
      Text(title).font(Font2.ui(12.5, .semibold)).foregroundStyle(color ?? pal.text2).lineLimit(1)
      if let pulse { pulse }
      Spacer(minLength: 4)
      trailing()
    }
    .frame(height: 18)
  }
}
extension WHead where Trailing == EmptyView {
  init(icon: String? = nil, title: String, color: Color? = nil) { self.init(icon: icon, title: title, color: color, trailing: { EmptyView() }) }
}

struct MoreLink: View {
  @Environment(\.pal) var pal
  let label: String
  let action: () -> Void
  var body: some View {
    Button(action: action) { Text(label).font(Font2.ui(11.5)).foregroundStyle(pal.text3) }.buttonStyle(.plain)
  }
}

struct Empty: View {
  @Environment(\.pal) var pal
  let text: String
  var body: some View {
    Text(text).font(Font2.ui(12.5)).foregroundStyle(pal.text3).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).padding(.top, 6)
  }
}

/** 标题下面能放几行 */
func fitRows(_ height: CGFloat, rowH: CGFloat, reserved: CGFloat = 26) -> Int { max(0, Int((height - reserved) / rowH)) }

// —— 时钟：iOS 锁屏的样子；小档是 iOS 时钟小组件那样的圆表盘 ——
struct ClockWidget: View {
  @Environment(\.pal) var pal
  let cell: Cell

  var body: some View {
    TimelineView(.everyMinute) { ctx in
      if cell.sizeKey == "S" { AnalogClock(date: ctx.date).padding(6) } else { digital(ctx.date) }
    }
  }

  private func digital(_ date: Date) -> some View {
    let now = date.timeIntervalSince1970 * 1000
    let t = ymd(now)
    let here = TimeZone.current.identifier
    // 和本地时间一样的城市就别再列一遍；不在同一天要带上星期（「北京 03:49」不说是哪天会被当成凌晨刚发生的事）
    let zones = [(L("北京"), "Asia/Shanghai"), (L("纽约"), "America/New_York")].filter { $0.1 != here && F.zoneTime($0.1, now) != F.hm(now) }
    let big = min(cell.size.height * 0.46, cell.size.width * 0.3)
    return VStack(alignment: .leading, spacing: 0) {
      Text(F.dateShort(now)).font(Font2.ui(13, .medium)).foregroundStyle(pal.text2)
      Text(F.hm(now)).font(Font2.round(big, .semibold)).foregroundStyle(pal.text).lineLimit(1).minimumScaleFactor(0.5)
      HStack(spacing: 10) {
        ForEach(zones, id: \.1) { z in
          let wd = F.zoneWeekday(z.1, now)
          Text("\(z.0) \(F.zoneTime(z.1, now))\(wd != F.week[t.wd] ? " · " + wd : "")")
        }
      }.font(Font2.num(12)).foregroundStyle(pal.text2)
      Spacer(minLength: 0)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }
}

struct AnalogClock: View {
  @Environment(\.pal) var pal
  let date: Date
  var body: some View {
    let c = Calendar.current.dateComponents([.hour, .minute], from: date)
    let m = Double(c.minute ?? 0), h = Double((c.hour ?? 0) % 12) + m / 60
    Canvas { ctx, size in
      let s = min(size.width, size.height), cx = size.width / 2, cy = size.height / 2, k = s / 100
      func pt(_ r: Double, _ a: Double) -> CGPoint { CGPoint(x: cx + CGFloat(r * Double(k) * Foundation.sin(a)), y: cy - CGFloat(r * Double(k) * Foundation.cos(a))) }
      for i in 0..<60 {
        let a = Double(i) * .pi / 30, major = i % 5 == 0
        var p = Path(); p.move(to: pt(major ? 41 : 44, a)); p.addLine(to: pt(47, a))
        ctx.stroke(p, with: .color(major ? pal.text : pal.text3), lineWidth: (major ? 1.6 : 0.8) * k)
      }
      for (n, a) in [(12, 0.0), (3, Double.pi / 2), (6, Double.pi), (9, Double.pi * 1.5)] {
        ctx.draw(Text("\(n)").font(.system(size: 11 * k, weight: .semibold, design: .rounded)).foregroundColor(pal.text), at: pt(30, a))
      }
      for (len, w, a) in [(19.0, 3.4, h * .pi / 6), (32.0, 2.2, m * .pi / 30)] {
        var p = Path(); p.move(to: pt(-2, a)); p.addLine(to: pt(len, a))
        ctx.stroke(p, with: .color(pal.text), style: StrokeStyle(lineWidth: w * k, lineCap: .round))
      }
      ctx.fill(Path(ellipseIn: CGRect(x: cx - 2.6 * k, y: cy - 2.6 * k, width: 5.2 * k, height: 5.2 * k)), with: .color(pal.orange))
    }
  }
}

// —— 天气 ——
func wxSymbol(_ icon: String) -> String {
  ["sun": "sun.max.fill", "moon": "moon.fill", "sun-cloud": "cloud.sun.fill", "moon-cloud": "cloud.moon.fill", "cloud": "cloud.fill",
   "fog": "cloud.fog.fill", "rain": "cloud.rain.fill", "snow": "cloud.snow.fill", "storm": "cloud.bolt.rain.fill"][icon] ?? "cloud.fill"
}

struct WeatherWidget: View {
  @Environment(\.pal) var pal
  @ObservedObject var model: DeskModel
  let cell: Cell

  var body: some View {
    if let w = model.cityWeather[cell.id] ?? model.weather {
      let d0 = w.days.first
      VStack(alignment: .leading, spacing: 4) {
        WHead(title: w.city) { if cell.interactive && cell.sizeKey != "S" { MoreLink(label: L("换城市 ›")) { model.page = "settings" } } }
        HStack(alignment: .center, spacing: 10) {
          Image(systemName: wxSymbol(w.now.icon)).symbolRenderingMode(.hierarchical).font(.system(size: cell.sizeKey == "S" ? 22 : 28)).foregroundStyle(pal.text)
          Text("\(w.now.temp)°").font(Font2.round(cell.sizeKey == "S" ? 30 : 40, .medium)).foregroundStyle(pal.text)
          if cell.sizeKey != "S" {
            VStack(alignment: .leading, spacing: 2) {
              Text(L("%@ · 体感 %@°", L(w.now.text), "\(w.now.feels)"))
              if let d0 { Text(L("最高 %@° 最低 %@°", "\(d0.max)", "\(d0.min)") + ((d0.rain ?? 0) > 0 ? L(" · 降水 %@%%", "\(d0.rain!)") : "")) }
            }.font(Font2.ui(12)).foregroundStyle(pal.text2)
          }
        }
        if cell.sizeKey == "S" {
          Text(L(w.now.text)).font(Font2.ui(12)).foregroundStyle(pal.text2)
        } else if cell.size.height > 150 {
          HStack(spacing: 0) {
            ForEach(Array(w.days.dropFirst().prefix(4).enumerated()), id: \.offset) { _, d in
              VStack(spacing: 3) {
                Text((F.dayLabel(dateMs(d.date)).components(separatedBy: " ").first ?? "").trimmingCharacters(in: CharacterSet(charactersIn: ","))).foregroundStyle(pal.text2)
                Image(systemName: wxSymbol(d.icon)).symbolRenderingMode(.hierarchical).font(.system(size: 15)).foregroundStyle(pal.text).frame(height: 18)
                Text("\(d.max)° ").foregroundStyle(pal.text) + Text("\(d.min)°").foregroundStyle(pal.text3)
              }.font(Font2.num(11.5)).frame(maxWidth: .infinity)
            }
          }.padding(.top, 2)
        }
        if w.stale { Text(L("更新失败，显示的是 %@ 的数据", F.rel(w.at))).font(Font2.ui(11)).foregroundStyle(pal.text3) }
        Spacer(minLength: 0)
      }
    } else {
      VStack(alignment: .leading) { WHead(title: L("天气")); Empty(text: L("加载中…")) }
    }
  }

  private func dateMs(_ s: String) -> Double {
    let p = s.components(separatedBy: "-").compactMap { Int($0) }
    return p.count == 3 ? localMs(p[0], p[1], p[2], 12) : 0
  }
}

// —— 日历：系统日历那样的红色月份 + 整月 + 选中日的日程 ——
struct CalendarWidget: View {
  @Environment(\.pal) var pal
  @ObservedObject var model: DeskModel
  let cell: Cell
  @State private var sel: String?

  var body: some View {
    let now = nowMs(), t = ymd(now)
    let today = F.dayKey(now)
    let cal = model.calendar
    let byDay = groupByDay(cal?.ok == true ? cal!.events : [])
    let showList = cell.size.height >= 300
    let showDots = cell.size.height >= 220
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        Text(F.monthName(t.m)).font(Font2.ui(15, .bold)).foregroundStyle(pal.red)
        Spacer()
        if cell.interactive { MoreLink(label: L("打开日历 ›")) { model.openApp("com.apple.iCal") } }
      }.frame(height: 18)
      monthGrid(t: t, today: today, byDay: byDay, dots: showDots)
      if showList { list(cal: cal, byDay: byDay, today: today, now: now) }
      Spacer(minLength: 0)
    }
  }

  private func groupByDay(_ events: [CalEvent]) -> [String: [CalEvent]] {
    var out: [String: [CalEvent]] = [:]
    for e in events {
      let s = ymd(e.start)
      let last = e.allDay ? e.end - 1 : e.end
      var i = 0
      var day = localMs(s.y, s.m, s.d)
      while day <= last && i < 40 {
        out[F.dayKey(day), default: []].append(e)
        i += 1
        day = localMs(s.y, s.m, s.d + i)
      }
    }
    return out
  }

  private func monthGrid(t: YMD, today: String, byDay: [String: [CalEvent]], dots: Bool) -> some View {
    let cells = F.monthCells(t.y, t.m)
    let selKey = sel ?? today
    return VStack(spacing: 2) {
      HStack(spacing: 0) {
        ForEach(Array(F.weekHeads.enumerated()), id: \.offset) { i, w in
          Text(w).font(Font2.ui(10.5, .medium)).foregroundStyle(i > 4 ? pal.text3 : pal.text2).frame(maxWidth: .infinity)
        }
      }
      ForEach(0..<6, id: \.self) { r in
        HStack(spacing: 0) {
          ForEach(0..<7, id: \.self) { c in
            let x = cells[r * 7 + c]
            let k = F.dayKey(x.ms)
            dayCell(x: x, key: k, isToday: k == today, isSel: k == selKey && k != today, evs: byDay[k] ?? [], dots: dots)
          }
        }
      }
    }
  }

  private func dayCell(x: (ms: Double, inMonth: Bool, day: Int, weekend: Bool), key: String, isToday: Bool, isSel: Bool, evs: [CalEvent], dots: Bool) -> some View {
    let fg: Color = isToday ? .white : !x.inMonth ? pal.text3.opacity(0.6) : x.weekend ? pal.text2 : pal.text
    let content = VStack(spacing: 1) {
      Text("\(x.day)").font(Font2.num(11.5, isToday ? .bold : .regular)).foregroundStyle(fg)
        .frame(width: 21, height: 21)
        .background(Circle().fill(isToday ? pal.red : .clear))
        .overlay(Circle().strokeBorder(isSel ? pal.text2 : .clear, lineWidth: 1))
      if dots {
        HStack(spacing: 2) {
          ForEach(Array(evs.prefix(3).enumerated()), id: \.offset) { _, e in Circle().fill(evColor(e)).frame(width: 3.5, height: 3.5) }
        }.frame(height: 4)
      }
    }.frame(maxWidth: .infinity)
    return Group {
      if cell.interactive {
        Button { sel = key == F.dayKey(nowMs()) ? nil : key } label: { content.contentShape(Rectangle()) }.buttonStyle(.plain)
      } else { content }
    }
  }

  private func evColor(_ e: CalEvent) -> Color {
    guard let c = e.color, c.count == 3 else { return pal.accent }
    return Color(r: Double(c[0]), g: Double(c[1]), b: Double(c[2]))
  }

  @ViewBuilder private func list(cal: CalendarState?, byDay: [String: [CalEvent]], today: String, now: Double) -> some View {
    if cal == nil {
      Empty(text: L("加载中…"))
    } else if let cal, !cal.ok {
      VStack(alignment: .leading, spacing: 6) {
        Text(cal.error ?? "").font(Font2.ui(12)).foregroundStyle(pal.text3)
        if cal.needAuth {
          if cell.interactive {
            Button(L("允许读取日历")) { Task { await model.askCalendar() } }.buttonStyle(PillButton())
          } else {
            Text(L("按 %@ 呼出后授权", F.hotkeyLabel(model.store.hotkey))).font(Font2.ui(12)).foregroundStyle(pal.text3)
          }
        } else {
          PrivacyButton(model: model, cell: cell, pane: "Privacy_Calendars")
        }
      }.padding(.top, 4)
    } else {
      let selKey = sel ?? today
      let label = selKey == today ? L("今天") : F.dayLabel(dayMs(selKey))
      let evs = (byDay[selKey] ?? []).filter { selKey != today || $0.end > now || $0.allDay }
        .sorted { ($0.allDay ? 0 : 1, $0.start) < ($1.allDay ? 0 : 1, $1.start) }
      // 选中日没日程：列「接下来」的
      let upcoming = evs.isEmpty ? (cal?.events ?? []).filter { $0.end > now && $0.start > dayMs(selKey) - 12 * 3600e3 }.sorted { $0.start < $1.start } : []
      let rows = fitRows(cell.size.height - 230, rowH: 36, reserved: 20)
      VStack(alignment: .leading, spacing: 5) {
        Rectangle().fill(pal.line).frame(height: 0.5)
        if !evs.isEmpty {
          Text(label).font(Font2.ui(11.5, .semibold)).foregroundStyle(pal.text2)
          ForEach(Array(evs.prefix(max(1, rows)).enumerated()), id: \.offset) { _, e in evRow(e, now: now, showDate: false) }
        } else if !upcoming.isEmpty {
          Text(L("%@没有日程 · 接下来", label)).font(Font2.ui(11.5, .semibold)).foregroundStyle(pal.text2)
          ForEach(Array(upcoming.prefix(max(1, rows)).enumerated()), id: \.offset) { _, e in evRow(e, now: now, showDate: true) }
        } else {
          Text(L("%@没有日程", label)).font(Font2.ui(12.5)).foregroundStyle(pal.text3)
        }
      }
    }
  }

  private func dayMs(_ key: String) -> Double {
    let p = key.components(separatedBy: "-").compactMap { Int($0) }
    return p.count == 3 ? localMs(p[0], p[1], p[2], 12) : nowMs()
  }

  private func evRow(_ e: CalEvent, now: Double, showDate: Bool) -> some View {
    let isNow = e.start <= now && e.end > now
    let d = ymd(e.start)
    return HStack(alignment: .top, spacing: 8) {
      RoundedRectangle(cornerRadius: 1.5).fill(evColor(e)).frame(width: 3, height: 30)
      VStack(alignment: .leading, spacing: 1) {
        Text(showDate ? "\(d.m)/\(d.d)" : (e.allDay ? L("全天") : F.hm(e.start)))
        Text(showDate ? (e.allDay ? L("全天") : F.hm(e.start)) : (e.allDay ? "" : F.hm(e.end))).foregroundStyle(pal.text3)
      }.font(Font2.num(10.5)).foregroundStyle(pal.text2).frame(width: 36, alignment: .leading)
      VStack(alignment: .leading, spacing: 1) {
        Text(e.title).font(Font2.ui(12.5, .medium)).foregroundStyle(pal.text).lineLimit(1)
        Text((isNow ? L("进行中 · ") : "") + (e.location.isEmpty ? e.calendar : e.location)).font(Font2.ui(11)).foregroundStyle(pal.text3).lineLimit(1)
      }
    }.frame(height: 32)
  }
}

struct PillButton: ButtonStyle {
  @Environment(\.pal) var pal
  func makeBody(configuration: Configuration) -> some View {
    configuration.label.font(Font2.ui(12, .medium)).foregroundStyle(pal.text)
      .padding(.horizontal, 12).padding(.vertical, 5)
      .background(Capsule().fill(configuration.isPressed ? pal.fill2 : pal.fill))
  }
}

// —— 行情：名字、现价、涨跌（默认中性 ▲▼）、状态点 ——
struct MarketWidget: View {
  @Environment(\.pal) var pal
  @ObservedObject var model: DeskModel
  let cell: Cell

  var body: some View {
    // 每个行情组件可以看自己的一组（设置里填）；没填就是全部自选
    let keys = (model.store.config(cell.id)["keys"] as? [String]).flatMap { $0.isEmpty ? nil : $0 } ?? model.store.watch
    let colors = model.store.colors
    let n = fitRows(cell.size.height - (model.marketError == nil ? 0 : 34), rowH: 30)
    VStack(alignment: .leading, spacing: 0) {
      WHead(icon: "chart.line.uptrend.xyaxis", title: widgetTitle(model, cell, L("行情"))) { if cell.interactive { MoreLink(label: L("全部自选 ›")) { model.page = "market" } } }
      VStack(spacing: 0) {
        ForEach(Array(keys.prefix(n).enumerated()), id: \.offset) { _, k in row(model.quotes[k], key: k, colors: colors) }
      }.padding(.top, 6)
      Spacer(minLength: 0)
      if let err = model.marketError {
        Text(L("行情获取失败：%@，显示的是上次的数字", err)).font(Font2.ui(11)).foregroundStyle(pal.text3).lineLimit(2)
      }
    }
    .help(L("新浪公开行情 · 延迟数据，仅供参考") + (model.marketAt > 0 ? " · 更新 " + F.hm(model.marketAt) : ""))
  }

  private func row(_ q: Quote?, key: String, colors: String) -> some View {
    let pct = q?.pct
    let mono = colors != "rup" && colors != "gup"
    return HStack(spacing: 8) {
      HStack(alignment: .firstTextBaseline, spacing: 5) {
        Text(appLang == "en" && q?.market != "cn" ? (q?.code ?? Market.displayCode(key)) : (q?.name ?? Market.displayCode(key))).font(Font2.ui(13, .medium)).foregroundStyle(pal.text).lineLimit(1)
        Text(q?.code ?? Market.displayCode(key)).font(Font2.num(10)).foregroundStyle(pal.text3).lineLimit(1)
      }
      Spacer(minLength: 4)
      Text(F.price(q?.price)).font(Font2.num(13)).foregroundStyle(pal.text)
      Text(mono ? F.pctMono(pct) : F.pct(pct))
        .font(Font2.num(12, (pct ?? 0) > 0 ? .semibold : .medium))
        .foregroundStyle(pal.change(pct, colors: colors))
        .frame(width: 70, alignment: .trailing)
      Circle().fill(dot(q?.status)).frame(width: 5, height: 5)
    }
    .frame(height: 30)
    .contentShape(Rectangle())
    .onTapGesture { if cell.interactive { model.symbolOpen = key } }
    .help(q.map { "\($0.name) \($0.code)\n\(F.statusText($0.status, $0.market))\($0.ts.map { "\n数据时间 " + F.rel($0) } ?? "")" } ?? "加载中")
  }

  private func dot(_ s: String?) -> Color {
    switch s {
    case "live": return pal.green
    case "stale": return pal.orange
    case "fail": return pal.red
    default: return pal.text3.opacity(0.7)
    }
  }
}

// —— 邮件：不画红色的总未读数（807 封是焦虑，不是信息），总数放在底部小字 ——
struct MailWidget: View {
  @Environment(\.pal) var pal
  @ObservedObject var model: DeskModel
  let cell: Cell

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      WHead(icon: "envelope", title: widgetTitle(model, cell, L("邮件"))) {
        if cell.interactive {
          MoreLink(label: L("概括重要邮件")) { model.page = "home"; Task { await model.digestMail(into: nil) } }.help(L("读几封重要邮件的正文，让管家概括"))
          MoreLink(label: L("打开邮件 ›")) { model.openApp("com.apple.mail") }
        }
      }
      content.padding(.top, 6)
      Spacer(minLength: 0)
    }
  }

  @ViewBuilder private var content: some View {
    if let m = model.mail {
      if !m.ok {
        VStack(alignment: .leading, spacing: 8) {
          Empty(text: m.notRunning ? L("打开「邮件」App 后，这里会显示未读邮件") : (m.error ?? ""))
          if (m.error ?? "").contains("自动化") { PrivacyButton(model: model, cell: cell, pane: "Privacy_Automation") }
          if m.notRunning && cell.interactive { Button(L("打开邮件")) { model.openApp("com.apple.mail") }.buttonStyle(PillButton()) }
        }
      } else if m.items.isEmpty {
        Empty(text: L("没有未读邮件"))
      } else {
        let n = fitRows(cell.size.height, rowH: 40, reserved: 44)
        VStack(alignment: .leading, spacing: 0) {
          ForEach(Array(m.items.prefix(max(1, n)).enumerated()), id: \.offset) { _, x in row(x) }
          Text(L("共 %@ 封未读", "\(m.unread)")).font(Font2.ui(11)).foregroundStyle(pal.text3).padding(.top, 4)
        }
      }
    } else {
      Empty(text: L("加载中…"))
    }
  }

  private func row(_ x: MailItem) -> some View {
    let body = HStack(spacing: 9) {
      Text(F.initials(x.name)).font(Font2.ui(10.5, .semibold)).foregroundStyle(.white)
        .frame(width: 26, height: 26).background(Circle().fill(Color(hex: F.avatarBg(x.name))))
      VStack(alignment: .leading, spacing: 1) {
        HStack {
          Text(x.name).font(Font2.ui(12.5, .semibold)).foregroundStyle(pal.text).lineLimit(1)
          Spacer(minLength: 4)
          Text(F.rel(x.ts)).font(Font2.num(10.5)).foregroundStyle(pal.text3)
        }
        Text(x.subject).font(Font2.ui(12)).foregroundStyle(pal.text2).lineLimit(1)
      }
    }.frame(height: 40).contentShape(Rectangle()).help(x.email)
    return Group {
      if cell.interactive && !x.id.isEmpty { Button { model.mailOpen = x.id } label: { body }.buttonStyle(.plain) } else { body }
    }
  }
}

// —— 新闻 ——
struct NewsWidget: View {
  @Environment(\.pal) var pal
  @ObservedObject var model: DeskModel
  let cell: Cell

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      WHead(icon: "newspaper", title: widgetTitle(model, cell, L("新闻"))) { if cell.interactive { MoreLink(label: L("更多 ›")) { model.page = "news" } } }
      if let n0 = model.news, !n0.items.isEmpty {
        // 每个新闻组件可以只看某个分类
        let tag = model.store.config(cell.id)["tag"] as? String ?? ""
        let n = NewsState(items: n0.items.filter { tag.isEmpty || $0.tag == tag })
        let rows = fitRows(cell.size.height, rowH: 58)
        VStack(alignment: .leading, spacing: 0) {
          ForEach(Array(n.items.prefix(max(1, rows)).enumerated()), id: \.offset) { _, x in row(x) }
        }.padding(.top, 6)
      } else {
        Empty(text: model.news?.error.map { "新闻获取失败：" + $0 } ?? "加载中…")
      }
      Spacer(minLength: 0)
    }
  }

  private func row(_ x: NewsItem) -> some View {
    let body = VStack(alignment: .leading, spacing: 2) {
      Text(x.title).font(Font2.ui(12.5, .medium)).foregroundStyle(pal.text).lineLimit(2).multilineTextAlignment(.leading)
      Text("\(x.tag) · \(x.source) · \(F.rel(x.ts))").font(Font2.ui(10.5)).foregroundStyle(pal.text3).lineLimit(1)
    }.frame(height: 58, alignment: .topLeading).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
    return Group {
      if cell.interactive { Button { model.openURL(x.link) } label: { body }.buttonStyle(.plain) } else { body }
    }
  }
}

// —— 管家：只说重要的事（可执行且意外）；有重要的新消息时闪蓝，在浮层里点一下熄灭 ——
struct ButlerWidget: View {
  @Environment(\.pal) var pal
  @ObservedObject var model: DeskModel
  let cell: Cell

  var body: some View {
    let day = model.butler
    let imp = day.important
    let name = widgetTitle(model, cell, model.store.butlerName)
    let isNew = model.hasNew
    VStack(alignment: .leading, spacing: 6) {
      WHead(icon: "sparkle", title: name, color: isNew ? pal.accent : nil, pulse: isNew ? Pulse(color: pal.accent, blinkForever: cell.interactive) : nil) {
        if !day.shown.isEmpty {
          if cell.interactive {
            MoreLink(label: L("今天 %@ 件", "\(day.shown.count)") + " ›") { model.markSeen(); model.page = "butler" }
          } else {
            Text(L("今天 %@ 件", "\(day.shown.count)")).font(Font2.ui(11.5)).foregroundStyle(pal.text3)
          }
        }
      }
      if let top = imp.first {
        Text(Brief.say(top)).font(Font2.ui(14.5, .medium)).foregroundStyle(pal.text).lineLimit(3).fixedSize(horizontal: false, vertical: true)
        ForEach(Array(imp.dropFirst().prefix(max(0, fitRows(cell.size.height, rowH: 20, reserved: 110))).enumerated()), id: \.offset) { _, c in
          HStack(alignment: .firstTextBaseline, spacing: 6) {
            Circle().fill(c.level == "notify" ? pal.accent : pal.text3).frame(width: 5, height: 5)
            Text(Brief.say(c)).font(Font2.ui(12)).foregroundStyle(pal.text2).lineLimit(1)
          }
        }
      } else {
        Text(L("今天没什么要说的")).font(Font2.ui(14.5, .medium)).foregroundStyle(pal.text2)
        Text(L("已经替你看了 %@ 件事，没有要紧的", "\(day.looked)")).font(Font2.ui(11.5)).foregroundStyle(pal.text3)
      }
      reminders
      Spacer(minLength: 0)
      if !cell.interactive && cell.size.height >= 150 {
        HStack(spacing: 6) {
          Text(L("按 %@ 问%@", F.hotkeyLabel(model.store.hotkey), name)).font(Font2.ui(12)).foregroundStyle(pal.text3)
          Spacer()
          Image(systemName: "arrow.up").font(.system(size: 11, weight: .semibold)).foregroundStyle(pal.text3)
        }
        .padding(.leading, 14).padding(.trailing, 10).frame(height: 30)
        .background(Capsule().fill(pal.fill))
      }
    }
    .padding(.leading, isNew ? 10 : 0)
    .overlay(alignment: .leading) { if isNew { Rectangle().fill(pal.accent).frame(width: 2) } }
    .contentShape(Rectangle())
    .onTapGesture { if cell.interactive { model.markSeen(); NotificationCenter.default.post(name: .focusAI, object: nil) } }
  }

  @ViewBuilder private var reminders: some View {
    let list = model.store.reminders.prefix(3)
    if !list.isEmpty && cell.size.height >= 200 {
      VStack(alignment: .leading, spacing: 3) {
        ForEach(Array(list.enumerated()), id: \.offset) { _, r in
          HStack(spacing: 8) {
            Text(r.time).font(Font2.num(11.5)).foregroundStyle(pal.text3)
            Text(r.title).font(Font2.ui(12)).foregroundStyle(pal.text2).lineLimit(1)
          }
        }
      }.padding(.top, 2)
    }
  }
}

/** 7px 的小点。桌面层只闪 8 下（12 秒）就停在亮着：无限动画会让全屏窗口一直合成画面，白白耗电 */
struct Pulse: View {
  let color: Color
  let blinkForever: Bool
  @State private var dim = false
  var body: some View {
    Circle().fill(color).frame(width: 7, height: 7).opacity(dim ? 0.18 : 1)
      .onAppear {
        withAnimation(.easeInOut(duration: 0.75).repeatCount(blinkForever ? 1_000_000 : 16, autoreverses: true)) { dim = true }
        if !blinkForever { DispatchQueue.main.asyncAfter(deadline: .now() + 12.2) { withAnimation(nil) { dim = false } } }
      }
  }
}

// —— 世界时钟：城市自己选（设置里），默认上海 + 本地 ——
let ZONES: [(id: String, name: String, en: String)] = [
  ("Asia/Shanghai", "上海", "Shanghai"), ("Asia/Hong_Kong", "香港", "Hong Kong"), ("Asia/Tokyo", "东京", "Tokyo"), ("Asia/Singapore", "新加坡", "Singapore"),
  ("Asia/Dubai", "迪拜", "Dubai"), ("Europe/London", "伦敦", "London"), ("Europe/Paris", "巴黎", "Paris"), ("Europe/Berlin", "柏林", "Berlin"),
  ("America/New_York", "纽约", "New York"), ("America/Chicago", "芝加哥", "Chicago"), ("America/Los_Angeles", "洛杉矶", "Los Angeles"),
  ("America/Toronto", "多伦多", "Toronto"), ("Australia/Sydney", "悉尼", "Sydney"), ("Asia/Seoul", "首尔", "Seoul"), ("Asia/Taipei", "台北", "Taipei"),
]
func zoneName(_ id: String) -> String {
  if let z = ZONES.first(where: { $0.id == id }) { return appLang == "en" ? z.en : z.name }
  return id.components(separatedBy: "/").last?.replacingOccurrences(of: "_", with: " ") ?? id
}

struct WorldClockWidget: View {
  @Environment(\.pal) var pal
  @ObservedObject var model: DeskModel
  let cell: Cell
  var body: some View {
    let zones = (model.store.config(cell.id)["zones"] as? [String]).flatMap { $0.isEmpty ? nil : $0 } ?? ["Asia/Shanghai"]
    TimelineView(.everyMinute) { ctx in
      let now = ctx.date.timeIntervalSince1970 * 1000
      VStack(alignment: .leading, spacing: 8) {
        WHead(icon: "clock", title: widgetTitle(model, cell, L("世界时钟")))
        ForEach(Array((zones + [TimeZone.current.identifier]).prefix(max(1, fitRows(cell.size.height, rowH: 30))).enumerated()), id: \.offset) { i, z in
          let tz = TimeZone(identifier: z) ?? .current
          let diff = (tz.secondsFromGMT(for: ctx.date) - TimeZone.current.secondsFromGMT(for: ctx.date)) / 3600
          let day = ymd(now, tz).d == ymd(now).d ? L("同日") : (diff > 0 ? L("次日") : L("前一日"))
          HStack(alignment: .firstTextBaseline) {
            Text(i == zones.count ? L("本地") : zoneName(z)).font(Font2.ui(13)).foregroundStyle(pal.text2).frame(width: 64, alignment: .leading).lineLimit(1)
            Text(F.zoneTime(z, now)).font(Font2.round(cell.sizeKey == "S" ? 17 : 22, .medium)).foregroundStyle(pal.text)
            Spacer()
            if cell.sizeKey != "S" { Text(i == zones.count ? zoneName(z) : "\(day) \(diff >= 0 ? "+" : "")\(diff)h").font(Font2.ui(11.5)).foregroundStyle(pal.text3) }
          }
        }
        Spacer(minLength: 0)
      }
    }
  }
}

// —— 风控：只读量化系统写的 risk 字段，不做任何建议 ——
struct RiskWidget: View {
  @Environment(\.pal) var pal
  @ObservedObject var model: DeskModel
  let cell: Cell
  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      WHead(icon: "exclamationmark.triangle", title: L("风控")) { if cell.interactive { MoreLink(label: L("个股 ›")) { model.page = "market" } } }
      if let q = model.quant, q.ok, let r = q.risk {
        let stop = model.store.riskStopPct
        let codes = model.store.riskCodes
        HStack(alignment: .firstTextBaseline, spacing: 8) {
          Text(F.pct(r.drawdown)).font(Font2.round(24, .medium)).foregroundStyle(pal.text)
          Text(L(F.riskText(r.status))).font(Font2.ui(11, .medium)).foregroundStyle(r.status == "normal" ? pal.text2 : pal.orange)
            .padding(.horizontal, 7).padding(.vertical, 2).background(Capsule().fill(pal.fill))
        }
        Text(L("半仓 %@%% · 清仓 %@%% · 预警 %@%%", r.halfLine.map(jsNum) ?? "—", r.exitLine.map(jsNum) ?? "—", jsNum(stop))).font(Font2.ui(11)).foregroundStyle(pal.text3)
        ForEach(Array(q.positions.filter { codes.isEmpty || codes.contains($0.code) }.prefix(2).enumerated()), id: \.offset) { _, p in
          HStack {
            Text(p.name).font(Font2.ui(12.5)).foregroundStyle(pal.text)
            Spacer()
            Text(F.pct(p.pnlPct)).font(Font2.num(12.5, .semibold)).foregroundStyle((p.pnlPct ?? 0) <= stop ? pal.orange : pal.text2)
          }
        }
      } else {
        Empty(text: L("没有读到量化数据"))
      }
      Spacer(minLength: 0)
    }
  }
}
