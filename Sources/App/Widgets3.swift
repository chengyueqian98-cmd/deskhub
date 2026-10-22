// 第三批组件：系统状态、便签、汇率、农历节日、正在播放。
import SwiftUI

// —— 系统状态 ——
struct SysWidget: View {
  @Environment(\.pal) var pal
  @ObservedObject var model: DeskModel
  let cell: Cell
  var body: some View {
    let s = model.sys
    VStack(alignment: .leading, spacing: 7) {
      WHead(icon: "cpu", title: widgetTitle(model, cell, L("系统状态")))
      if cell.sizeKey == "S" {
        bar("CPU", s.cpu); bar(L("内存"), s.mem)
      } else {
        bar("CPU", s.cpu)
        bar(L("内存"), s.mem)
        if let f = s.diskFree, let t = s.diskTotal, t > 0 {
          bar(L("磁盘"), Int(((t - f) / t * 100).rounded()), note: L("剩 %@", SysSampler.gb(f)))
        }
        HStack(spacing: 14) {
          Label(SysSampler.speed(s.down), systemImage: "arrow.down")
          Label(SysSampler.speed(s.up), systemImage: "arrow.up")
          if let b = s.battery { Label("\(b)%", systemImage: s.charging ? "battery.100.bolt" : "battery.75") }
        }.font(Font2.num(11.5)).foregroundStyle(pal.text2)
      }
      Spacer(minLength: 0)
    }
  }
  private func bar(_ name: String, _ v: Int?, note: String = "") -> some View {
    let x = v ?? 0
    return HStack(spacing: 8) {
      Text(name).font(Font2.ui(11.5)).foregroundStyle(pal.text2).frame(width: 34, alignment: .leading)
      ZStack(alignment: .leading) {
        Capsule().fill(pal.fill2)
        Capsule().fill(x >= 85 ? pal.orange : pal.accent).frame(width: max(2, CGFloat(x) / 100 * (cell.size.width - (note.isEmpty ? 100 : 170))))
      }.frame(height: 5)
      Text(v.map { "\($0)%" } ?? "—").font(Font2.num(12, .medium)).foregroundStyle(pal.text).frame(width: 38, alignment: .trailing)
      if !note.isEmpty { Text(note).font(Font2.ui(10.5)).foregroundStyle(pal.text3).frame(width: 64, alignment: .trailing) }
    }
  }
}

// —— 便签：桌面上显示，浮层里直接改（停手一秒自动保存） ——
struct NoteWidget: View {
  @Environment(\.pal) var pal
  @ObservedObject var model: DeskModel
  let cell: Cell
  @State private var text = ""
  @State private var save: Task<Void, Never>?

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      WHead(icon: "note.text", title: widgetTitle(model, cell, L("便签")))
      if cell.interactive {
        TextEditor(text: $text)
          .font(Font2.ui(13)).foregroundStyle(pal.text).scrollContentBackground(.hidden)
          .padding(4).background(RoundedRectangle(cornerRadius: 8).fill(pal.fill))
          .onChange(of: text) { _, v in
            save?.cancel()
            save = Task { try? await Task.sleep(nanoseconds: 800_000_000); guard !Task.isCancelled else { return }
              var c = model.store.config(cell.id); c["text"] = v; model.store.setConfig(cell.id, c) }
          }
      } else {
        let t = model.store.config(cell.id)["text"] as? String ?? ""
        Text(t.isEmpty ? L("在浮层里点这里写点什么") : t).font(Font2.ui(13)).foregroundStyle(t.isEmpty ? pal.text3 : pal.text)
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      }
    }
    .onAppear { text = model.store.config(cell.id)["text"] as? String ?? "" }
  }
}

// —— 汇率 ——
struct FXWidget: View {
  @Environment(\.pal) var pal
  @ObservedObject var model: DeskModel
  let cell: Cell
  var body: some View {
    let c = model.store.config(cell.id)
    let base = c["base"] as? String ?? (appLang == "en" ? "USD" : "CNY")
    let targets = (c["targets"] as? [String]).flatMap { $0.isEmpty ? nil : $0 } ?? (base == "CNY" ? ["USD", "EUR", "JPY", "HKD"] : ["CNY", "EUR", "JPY", "GBP"])
    let amount = num(c["amount"]) ?? (base == "CNY" ? 100 : 1)
    VStack(alignment: .leading, spacing: 0) {
      WHead(icon: "dollarsign.arrow.circlepath", title: widgetTitle(model, cell, L("汇率"))) {
        Text("\(jsNum(amount)) \(base)").font(Font2.num(11)).foregroundStyle(pal.text3)
      }
      if let r = model.fx[cell.id] {
        VStack(spacing: 0) {
          ForEach(Array(targets.prefix(max(1, fitRows(cell.size.height, rowH: 28))).enumerated()), id: \.offset) { _, t in
            HStack {
              Text(t).font(Font2.ui(13, .medium)).foregroundStyle(pal.text)
              Text(appLang == "en" ? "" : FX.names[t] ?? "").font(Font2.ui(11)).foregroundStyle(pal.text3)
              Spacer()
              Text(r.rates[t].map { F.num($0 * amount, $0 * amount >= 100 ? 2 : 4) } ?? "—").font(Font2.num(13)).foregroundStyle(pal.text)
            }.frame(height: 28)
          }
        }.padding(.top, 6)
      } else { Empty(text: L("加载中…")) }
      Spacer(minLength: 0)
    }
    .help(L("open.er-api.com 公开汇率，每天更新，仅供参考"))
  }
}

// —— 农历和最近的节日 ——
struct LunarWidget: View {
  @Environment(\.pal) var pal
  @ObservedObject var model: DeskModel
  let cell: Cell
  var body: some View {
    TimelineView(.everyMinute) { ctx in
      let now = ctx.date.timeIntervalSince1970 * 1000
      let next = Lunar.next(now)
      VStack(alignment: .leading, spacing: 4) {
        WHead(icon: "moon.stars", title: widgetTitle(model, cell, L("农历")))
        Text(Lunar.text(now)).font(Font2.ui(cell.sizeKey == "S" ? 17 : 20, .semibold)).foregroundStyle(pal.text).lineLimit(1).minimumScaleFactor(0.6)
        if let n = next {
          Text(n.days == 0 ? L("今天是%@", L(n.name)) : L("%@ · 还有 %@ 天", L(n.name), "\(n.days)")).font(Font2.ui(12)).foregroundStyle(n.days == 0 ? pal.accent : pal.text2).lineLimit(1)
        }
        Spacer(minLength: 0)
      }
    }
  }
}

// —— 正在播放（Apple Music / Spotify） ——
struct NowPlayingWidget: View {
  @Environment(\.pal) var pal
  @ObservedObject var model: DeskModel
  let cell: Cell
  var body: some View {
    let np = model.nowPlaying
    TimelineView(.periodic(from: .now, by: np?.playing == true ? 1 : 3600)) { ctx in
      VStack(alignment: .leading, spacing: 6) {
        WHead(icon: "music.note", title: widgetTitle(model, cell, L("正在播放"))) { if let np { Text(np.app).font(Font2.ui(11)).foregroundStyle(pal.text3) } }
        if let np {
          HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 8).fill(LinearGradient(colors: [pal.accent.opacity(0.7), pal.orange.opacity(0.5)], startPoint: .topLeading, endPoint: .bottomTrailing))
              .frame(width: 44, height: 44).overlay(Image(systemName: "music.note").foregroundStyle(.white.opacity(0.9)))
            VStack(alignment: .leading, spacing: 2) {
              Text(np.title).font(Font2.ui(13.5, .semibold)).foregroundStyle(pal.text).lineLimit(1)
              Text(np.artist).font(Font2.ui(12)).foregroundStyle(pal.text2).lineLimit(1)
            }
            Spacer(minLength: 0)
            if cell.interactive {
              HStack(spacing: 10) {
                ctl("backward.fill", "previous track"); ctl(np.playing ? "pause.fill" : "play.fill", "playpause"); ctl("forward.fill", "next track")
              }
            }
          }
          if np.duration > 0 {
            let p = np.pos(ctx.date)
            HStack(spacing: 8) {
              Text(mmss(p)).font(Font2.num(10.5)).foregroundStyle(pal.text3)
              ZStack(alignment: .leading) {
                Capsule().fill(pal.fill2)
                GeometryReader { g in Capsule().fill(pal.text2).frame(width: g.size.width * CGFloat(min(1, p / np.duration))) }
              }.frame(height: 4)
              Text(mmss(np.duration)).font(Font2.num(10.5)).foregroundStyle(pal.text3)
            }
          }
        } else {
          Empty(text: L("Apple Music 或 Spotify 放歌时显示在这里"))
        }
        Spacer(minLength: 0)
      }
    }
  }
  private func ctl(_ icon: String, _ cmd: String) -> some View {
    Button { model.playerCommand(cmd) } label: { Image(systemName: icon).font(.system(size: 13)).foregroundStyle(pal.text) }.buttonStyle(.plain)
  }
  private func mmss(_ s: Double) -> String { String(format: "%d:%02d", Int(s) / 60, Int(s) % 60) }
}
