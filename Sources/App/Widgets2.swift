// 新组件：待办、倒数日、加密货币、GitHub、订阅、照片、番茄钟。和老组件一样：没有底色、一条发丝线分隔、装不下就少显示几行。
// 同一种可以加好几个，每个读自己的设置（store.config(组件 id)）。
import SwiftUI
import ImageIO

/** 组件标题：用户改过名字就用他的名字 */
@MainActor func widgetTitle(_ model: DeskModel, _ cell: Cell, _ fallback: String) -> String {
  let n = model.layoutFor("main").item(cell.id)?.name ?? ""
  return n.isEmpty ? fallback : n
}

/** 去系统设置打开权限的按钮（被拒绝过之后系统不会再弹框） */
struct PrivacyButton: View {
  @ObservedObject var model: DeskModel
  let cell: Cell
  let pane: String
  var body: some View {
    if cell.interactive {
      Button(L("去系统设置打开")) { model.openPrivacy(pane) }.buttonStyle(PillButton())
    } else {
      Text(L("按 %@ 呼出后处理", F.hotkeyLabel(model.store.hotkey))).font(Font2.ui(12)).foregroundStyle(Palette.make(dark: true).text3)
    }
  }
}

// —— 待办（系统「提醒事项」） ——
struct TodoWidget: View {
  @Environment(\.pal) var pal
  @ObservedObject var model: DeskModel
  let cell: Cell

  var body: some View {
    let listId = model.store.config(cell.id)["list"] as? String ?? ""
    VStack(alignment: .leading, spacing: 0) {
      WHead(icon: "checklist", title: widgetTitle(model, cell, L("待办")))
      if let t = model.todos {
        if !t.ok {
          VStack(alignment: .leading, spacing: 8) {
            Text(t.error ?? "").font(Font2.ui(12.5)).foregroundStyle(pal.text3)
            if t.needAuth {
              if cell.interactive { Button(L("允许读取提醒事项")) { Task { await model.askReminders() } }.buttonStyle(PillButton()) }
            } else { PrivacyButton(model: model, cell: cell, pane: "Privacy_Reminders") }
          }.padding(.top, 6)
        } else {
          let items = t.items.filter { listId.isEmpty || $0.listId == listId }
          if items.isEmpty { Empty(text: L("没有待办，干得好")) }
          VStack(alignment: .leading, spacing: 0) {
            ForEach(items.prefix(max(1, fitRows(cell.size.height, rowH: 30)))) { x in row(x) }
          }.padding(.top, 6)
        }
      } else { Empty(text: L("加载中…")) }
      Spacer(minLength: 0)
    }
    .onAppear { if model.todos == nil { model.refreshTodos() } }
  }

  private func row(_ x: TodoItem) -> some View {
    let late = (x.due ?? .greatestFiniteMagnitude) < nowMs()
    return HStack(spacing: 9) {
      Button { if cell.interactive { model.completeTodo(x.id) } } label: {
        Circle().strokeBorder(x.color.map { Color(r: Double($0[0]), g: Double($0[1]), b: Double($0[2])) } ?? pal.text3, lineWidth: 1.4).frame(width: 15, height: 15)
      }.buttonStyle(.plain).help(L("完成"))
      Text(x.title).font(Font2.ui(13)).foregroundStyle(pal.text).lineLimit(1)
      Spacer(minLength: 4)
      if let d = x.due { Text(F.dayLabel(d)).font(Font2.ui(11)).foregroundStyle(late ? pal.orange : pal.text3) }
    }.frame(height: 30)
  }
}

// —— 倒数日 ——
struct CountdownWidget: View {
  @Environment(\.pal) var pal
  @ObservedObject var model: DeskModel
  let cell: Cell

  var body: some View {
    let items = (model.store.config(cell.id)["items"] as? [JSON] ?? []).compactMap { j -> (String, Int)? in
      guard let t = j["title"] as? String, let d = Countdown.days(j["date"] as? String ?? "") else { return nil }
      return (t, d)
    }.sorted { abs($0.1) < abs($1.1) }
    TimelineView(.everyMinute) { _ in
      VStack(alignment: .leading, spacing: 6) {
        WHead(icon: "calendar.badge.clock", title: widgetTitle(model, cell, L("倒数日")))
        if let first = items.first {
          Text(first.0).font(Font2.ui(13)).foregroundStyle(pal.text2).lineLimit(1)
          HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(first.1 >= 0 ? L("还有") : L("已经")).font(Font2.ui(12)).foregroundStyle(pal.text3)
            Text("\(abs(first.1))").font(Font2.round(cell.sizeKey == "S" ? 30 : 38, .semibold)).foregroundStyle(pal.text)
            Text(L("天")).font(Font2.ui(12)).foregroundStyle(pal.text3)
          }
          ForEach(Array(items.dropFirst().prefix(max(0, fitRows(cell.size.height, rowH: 22, reserved: 110))).enumerated()), id: \.offset) { _, x in
            HStack {
              Text(x.0).font(Font2.ui(12)).foregroundStyle(pal.text2).lineLimit(1)
              Spacer()
              Text(x.1 >= 0 ? L("%@ 天", "\(x.1)") : L("已过 %@ 天", "\(-x.1)")).font(Font2.num(12)).foregroundStyle(pal.text3)
            }
          }
        } else {
          Empty(text: cell.interactive ? L("点「编辑」里的齿轮，加一个日子") : L("还没有设置日子"))
        }
        Spacer(minLength: 0)
      }
    }
  }
}

// —— 加密货币 ——
struct CryptoWidget: View {
  @Environment(\.pal) var pal
  @ObservedObject var model: DeskModel
  let cell: Cell

  var body: some View {
    let vs = model.store.config(cell.id)["vs"] as? String ?? "usd"
    let colors = model.store.colors
    VStack(alignment: .leading, spacing: 0) {
      WHead(icon: "bitcoinsign.circle", title: widgetTitle(model, cell, L("加密货币"))) { Text(vs.uppercased()).font(Font2.ui(11)).foregroundStyle(pal.text3) }
      if let list = model.crypto[cell.id], !list.isEmpty {
        VStack(spacing: 0) {
          ForEach(Array(list.prefix(max(1, fitRows(cell.size.height, rowH: 30))).enumerated()), id: \.offset) { _, q in
            HStack {
              Text(Crypto.symbol[q.id] ?? q.id.uppercased()).font(Font2.ui(13, .medium)).foregroundStyle(pal.text)
              Spacer()
              Text(F.num(q.price, q.price >= 100 ? 0 : q.price >= 1 ? 2 : 4)).font(Font2.num(13)).foregroundStyle(pal.text)
              Text(colors == "mono" || colors.isEmpty ? F.pctMono(q.change) : F.pct(q.change)).font(Font2.num(12, .semibold))
                .foregroundStyle(pal.change(q.change, colors: colors)).frame(width: 70, alignment: .trailing)
            }.frame(height: 30)
          }
        }.padding(.top, 6)
      } else { Empty(text: L("加载中…")) }
      Spacer(minLength: 0)
    }
    .help(L("CoinGecko 公开行情，仅供参考"))
  }
}

// —— GitHub：仓库的 Star、Fork、Issue 和安装包下载次数 ——
struct GitHubWidget: View {
  @Environment(\.pal) var pal
  @ObservedObject var model: DeskModel
  let cell: Cell

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      WHead(icon: "chevron.left.forwardslash.chevron.right", title: widgetTitle(model, cell, "GitHub"))
      let list = model.repos[cell.id] ?? []
      if list.isEmpty {
        Empty(text: (model.store.config(cell.id)["repos"] as? [String] ?? []).isEmpty ? L("在设置里填仓库，比如 apple/swift") : L("加载中…"))
      }
      ForEach(Array(list.prefix(max(1, fitRows(cell.size.height, rowH: 44))).enumerated()), id: \.offset) { _, r in
        VStack(alignment: .leading, spacing: 3) {
          Text(r.name).font(Font2.ui(13, .medium)).foregroundStyle(pal.text).lineLimit(1)
          HStack(spacing: 12) {
            Label("\(r.stars)", systemImage: "star")
            Label("\(r.forks)", systemImage: "tuningfork")
            Label("\(r.issues)", systemImage: "smallcircle.filled.circle")
            if let d = r.downloads { Label("\(d)", systemImage: "arrow.down.circle") }
          }.font(Font2.num(11.5)).foregroundStyle(pal.text2).labelStyle(.titleAndIcon)
        }
        .contentShape(Rectangle())
        .onTapGesture { if cell.interactive { model.openURL("https://github.com/" + r.name) } }
      }
      Spacer(minLength: 0)
    }
  }
}

// —— 订阅（任意 RSS / Atom） ——
struct FeedWidget: View {
  @Environment(\.pal) var pal
  @ObservedObject var model: DeskModel
  let cell: Cell

  var body: some View {
    let f = model.feeds[cell.id]
    VStack(alignment: .leading, spacing: 0) {
      WHead(icon: "dot.radiowaves.up.forward", title: widgetTitle(model, cell, f?.items.first?.source ?? L("订阅")))
      if let f, !f.items.isEmpty {
        VStack(alignment: .leading, spacing: 0) {
          ForEach(Array(f.items.prefix(max(1, fitRows(cell.size.height, rowH: 50))).enumerated()), id: \.offset) { _, x in
            VStack(alignment: .leading, spacing: 2) {
              Text(x.title).font(Font2.ui(12.5, .medium)).foregroundStyle(pal.text).lineLimit(2)
              Text(F.rel(x.ts)).font(Font2.ui(10.5)).foregroundStyle(pal.text3)
            }
            .frame(height: 50, alignment: .topLeading).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            .onTapGesture { if cell.interactive { model.openURL(x.link) } }
          }
        }.padding(.top, 6)
      } else {
        Empty(text: f?.error.map { L("读取失败：") + $0 } ?? ((model.store.config(cell.id)["url"] as? String) == nil ? L("在设置里填订阅地址（RSS 或 Atom）") : L("加载中…")))
      }
      Spacer(minLength: 0)
    }
  }
}

// —— 照片：从你选的文件夹里轮着显示（按格子大小缩小后再读进内存，大图不会撑爆内存） ——
struct PhotoWidget: View {
  @Environment(\.pal) var pal
  @ObservedObject var model: DeskModel
  let cell: Cell
  @State private var img: NSImage?
  @State private var path = ""

  var body: some View {
    ZStack {
      if let img {
        Image(nsImage: img).resizable().aspectRatio(contentMode: .fill).frame(width: cell.size.width, height: cell.size.height - 10).clipped()
          .clipShape(RoundedRectangle(cornerRadius: 14))
      } else {
        VStack(alignment: .leading) {
          WHead(icon: "photo", title: widgetTitle(model, cell, L("照片")))
          Empty(text: model.photos[cell.id] == "" ? L("这个文件夹里没有照片，在设置里换一个") : L("加载中…"))
        }
      }
    }
    .onAppear { if model.photos[cell.id] == nil { model.rotatePhotos() } }
    .task(id: (model.photos[cell.id] ?? "") + "\(Int(cell.size.width))") { load() }
    .contentShape(Rectangle())
    .onTapGesture { if cell.interactive { model.rotatePhotos() } }
  }

  private func load() {
    guard let p = model.photos[cell.id], !p.isEmpty, p != path || img == nil else { return }
    path = p
    let maxPx = max(cell.size.width, cell.size.height) * 2
    guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: p) as CFURL, nil),
          let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: maxPx, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) else { img = nil; return }
    img = NSImage(cgImage: cg, size: .zero)
  }
}

// —— 番茄钟：浮层里开始 / 暂停 / 重来；桌面上显示还剩多少 ——
struct PomodoroWidget: View {
  @Environment(\.pal) var pal
  @ObservedObject var model: DeskModel
  let cell: Cell

  var body: some View {
    let p = model.pomo
    // 只在跑的时候每秒刷新（停着的时候不重画，不费电）
    TimelineView(.periodic(from: .now, by: p.running ? 1 : 3600)) { ctx in
      let left = p.remaining(ctx.date)
      VStack(alignment: .leading, spacing: 6) {
        WHead(icon: "timer", title: widgetTitle(model, cell, L("番茄钟")))
        ZStack {
          Circle().stroke(pal.fill2, lineWidth: 4)
          Circle().trim(from: 0, to: CGFloat(p.total > 0 ? left / p.total : 0)).stroke(pal.accent, style: StrokeStyle(lineWidth: 4, lineCap: .round)).rotationEffect(.degrees(-90))
          Text(String(format: "%02d:%02d", Int(left) / 60, Int(left) % 60)).font(Font2.round(cell.sizeKey == "S" ? 20 : 26, .medium)).foregroundStyle(pal.text)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity).padding(4)
        if cell.interactive {
          HStack(spacing: 6) {
            Button(p.running ? L("暂停") : L("开始")) { p.running ? model.pomoPause() : model.pomoStart() }.buttonStyle(PillButton())
            Button(L("重来")) { model.pomoReset(num(model.store.config(cell.id)["minutes"])) }.buttonStyle(MiniButton())
          }.frame(maxWidth: .infinity)
        }
      }
    }
  }
}
