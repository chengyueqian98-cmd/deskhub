// 两个根视图：桌面层（只显示）和浮层（顶栏 + 主页网格 / 管家页 + 编排条）。
// 两边的网格区域完全一样（同一组边距），呼出浮层时组件不会跳位置。
import SwiftUI

/** 网格区域的边距：菜单栏、程序坞让开；上面再留一条给浮层的顶栏 */
struct Insets { var top: CGFloat, left: CGFloat, bottom: CGFloat, right: CGFloat }
let TOPBAR: CGFloat = 46

struct DeskRoot: View {
  @Environment(\.colorScheme) var scheme
  @ObservedObject var model: DeskModel
  let insets: Insets
  var screenKey = "main"

  var body: some View {
    let pal = Palette.make(dark: scheme == .dark, theme: model.theme)
    ZStack {
      // 没有底色就靠两侧一层很淡的渐隐保证读得清：深色外观是黑雾，浅色外观是白雾
      LinearGradient(stops: [
        .init(color: pal.veil, location: 0), .init(color: pal.veil2, location: 0.2), .init(color: .clear, location: 0.33),
        .init(color: .clear, location: 0.67), .init(color: pal.veil2, location: 0.8), .init(color: pal.veil, location: 1),
      ], startPoint: .leading, endPoint: .trailing)
      GridView(model: model, interactive: false, screenKey: screenKey)
        .shadow(color: pal.glow, radius: pal.dark ? 5 : 4, x: 0, y: pal.dark ? 1 : 0)
        .padding(EdgeInsets(top: insets.top + TOPBAR, leading: insets.left, bottom: insets.bottom, trailing: insets.right))
    }
    .environment(\.pal, pal)
  }
}

struct OverlayRoot: View {
  @ObservedObject var model: DeskModel
  let insets: Insets
  let close: () -> Void
  var openConsole: (Chat?) -> Void = { _ in }
  @StateObject private var launcher = LauncherModel()
  @State private var launcherOpen = Snapshot.launcher ?? UserDefaults.standard.bool(forKey: "launcher.open")

  var body: some View {
    let pal = Palette.make(dark: true, theme: model.theme)
    ZStack(alignment: .top) {
      Color.black.opacity(0.18).ignoresSafeArea()
      Group {
        switch model.page {
        case "home":
          GridView(model: model, interactive: true, screenKey: model.overlayKey)
            .padding(EdgeInsets(top: insets.top + TOPBAR, leading: insets.left, bottom: insets.bottom, trailing: insets.right))
        default:
          page.padding(.top, insets.top + TOPBAR)
        }
      }
      TopBar(model: model, close: close, openConsole: { openConsole(nil) }).padding(.top, insets.top + 8)
      if model.editing && model.page == "home" {
        EditBar(model: model).frame(maxHeight: .infinity, alignment: .bottom).padding(.bottom, insets.bottom + 18)
      } else if model.page == "home" {
        // 主页中间那片空地：对话和启动器在这里展开
        VStack(spacing: 12) {
          Spacer()
          if launcherOpen { LauncherPanel(lm: launcher) }
          AIBar(model: model, chat: model.overlayChat, launcherOpen: $launcherOpen, openConsole: { openConsole($0) })
        }
        .padding(.bottom, insets.bottom + 18)
      }
      if let id = model.mailOpen { MailPanel(model: model, id: id) }
      if let id = model.configOpen { WidgetConfigPanel(model: model, id: id).id(id) }
      if let k = model.symbolOpen { SymbolPanel(model: model, key: k) }
      if let t = model.toast {
        Text(t).font(Font2.ui(12.5, .medium)).foregroundStyle(pal.text).padding(.horizontal, 16).padding(.vertical, 8)
          .background(Capsule().fill(.black.opacity(0.6))).overlay(Capsule().strokeBorder(pal.line, lineWidth: 0.5))
          .frame(maxHeight: .infinity, alignment: .bottom).padding(.bottom, insets.bottom + 90)
          .task(id: t) { try? await Task.sleep(nanoseconds: 3_000_000_000); if model.toast == t { model.toast = nil } }
      }
    }
    .environment(\.pal, pal)
    .environment(\.colorScheme, .dark)
    .onChange(of: launcherOpen) { _, v in UserDefaults.standard.set(v, forKey: "launcher.open") }
    .onReceive(NotificationCenter.default.publisher(for: .toggleLauncher)) { _ in model.page = "home"; launcherOpen.toggle() }
  }

  /** 二级页面：居中一栏，自己滚 */
  @ViewBuilder private var page: some View {
    MaybeScroll {
      Group {
        switch model.page {
        case "butler": VStack(alignment: .leading, spacing: 28) { ButlerPage(model: model); RemindersSection(model: model) }
        case "market": MarketPage(model: model)
        case "news": NewsPage(model: model)
        default: SettingsPage(model: model)
        }
      }
      .frame(maxWidth: model.page == "market" ? 1240 : 900)
      .frame(maxWidth: .infinity)
      .padding(.horizontal, 40).padding(.vertical, 12).padding(.bottom, 60)
    }
  }
}

extension Notification.Name { static let toggleLauncher = Notification.Name("deskhub.toggleLauncher") }

struct TopBar: View {
  @Environment(\.pal) var pal
  @ObservedObject var model: DeskModel
  let close: () -> Void
  var openConsole: () -> Void = {}

  var body: some View {
    ZStack {
      HStack(spacing: 2) {
        tab(L("主页"), "home")
        tab(model.store.butlerName, "butler")
        tab(L("市场"), "market")
        tab(L("新闻"), "news")
        tab(L("设置"), "settings")
      }
      .padding(3).background(Capsule().fill(pal.fill))
      HStack(spacing: 14) {
        Spacer()
        if let u = model.update {
          Button { model.openURL(u.page) } label: {
            Label(L("新版本 %@", u.version), systemImage: "arrow.down.circle.fill").font(Font2.ui(11.5, .medium)).foregroundStyle(.white)
              .padding(.horizontal, 10).padding(.vertical, 4).background(Capsule().fill(pal.accent))
          }.buttonStyle(.plain).help(u.notes.isEmpty ? L("去下载") : u.notes)
        }
        BatteryBar(devices: model.battery)
        if model.page == "home" {
          Button(model.editing ? L("完成") : L("编辑")) { model.editing.toggle() }.buttonStyle(PillButton())
        }
        Button { openConsole() } label: { Image(systemName: "bubble.left.and.text.bubble.right").font(.system(size: 12)).foregroundStyle(pal.text2).frame(width: 26, height: 26).background(Circle().fill(pal.fill)) }
          .buttonStyle(.plain).help(L("AI 总控台（⌘0）"))
        Button { close() } label: { Image(systemName: "xmark").font(.system(size: 11, weight: .semibold)).foregroundStyle(pal.text2).frame(width: 26, height: 26).background(Circle().fill(pal.fill)) }
          .buttonStyle(.plain).help(L("收起（Esc）"))
      }
      .padding(.horizontal, 24)
    }
    .frame(height: 32)
  }

  private func tab(_ title: String, _ page: String) -> some View {
    Button {
      model.page = page
      model.editing = false
      if page == "butler" { model.markSeen() }
    } label: {
      Text(title).font(Font2.ui(13, .medium)).foregroundStyle(model.page == page ? pal.text : pal.text2)
        .padding(.horizontal, 16).padding(.vertical, 5)
        .background(Capsule().fill(model.page == page ? pal.fill2 : .clear))
        .overlay(alignment: .topTrailing) {
          if page == "butler" && model.hasNew { Circle().fill(pal.accent).frame(width: 6, height: 6).offset(x: -6, y: 4) }
        }
    }.buttonStyle(.plain)
  }
}

/** 电量：最多 3 个设备，图标 + 百分比；低于 20% 且没在充电变红；悬停看全部 */
struct BatteryBar: View {
  @Environment(\.pal) var pal
  let devices: [BatteryDevice]
  var body: some View {
    HStack(spacing: 10) {
      ForEach(Array(devices.prefix(3).enumerated()), id: \.offset) { _, d in
        let low = d.pct <= 20 && !d.charging
        HStack(spacing: 4) {
          Image(systemName: icon(d.type)).font(.system(size: 11))
          Text("\(d.pct)%").font(Font2.num(11.5, .medium))
          if d.charging { Image(systemName: "bolt.fill").font(.system(size: 8)) }
        }.foregroundStyle(low ? pal.red : pal.text2)
      }
    }
    .help(devices.map { d in
      let state = d.charging ? L("充电中") : (d.charged || (d.ac && d.pct >= 99)) ? L("已充满") : d.ac ? L("接电源") : ""
      return "\(d.internal ? "Mac" : BatteryInfo.shortName(d.name)) \(d.pct)%\(state.isEmpty ? "" : " · " + state)"
    }.joined(separator: "\n"))
  }
  private func icon(_ t: String) -> String {
    ["laptop": "laptopcomputer", "headphones": "headphones", "mouse": "computermouse", "keyboard": "keyboard",
     "trackpad": "hand.point.up.left", "speaker": "hifispeaker"][t] ?? "battery.75percent"
  }
}

/** 编排条：加回收起的组件、恢复默认、完成 */
struct EditBar: View {
  @Environment(\.pal) var pal
  @ObservedObject var model: DeskModel
  var body: some View {
    HStack(spacing: 8) {
      AddWidgetMenu(model: model)
      Rectangle().fill(pal.line).frame(width: 0.5, height: 18)
      Button(L("恢复默认")) { model.resetLayout() }.buttonStyle(PillButton())
      Button { model.editing = false } label: {
        Text(L("完成")).font(Font2.ui(12, .semibold)).foregroundStyle(.white).padding(.horizontal, 14).padding(.vertical, 5).background(Capsule().fill(pal.accent))
      }.buttonStyle(.plain)
    }
    .padding(.horizontal, 14).padding(.vertical, 9)
    .background(Capsule().fill(.black.opacity(0.35)))
    .overlay(Capsule().strokeBorder(pal.line, lineWidth: 0.5))
  }
}

/** 管家页：三段——现在 / 等你呼出浮层才看到 / 其它。每条可以看证据、点「晚点」先拿掉 */
struct ButlerPage: View {
  @Environment(\.pal) var pal
  @ObservedObject var model: DeskModel
  @State private var openEv: Set<String> = []

  var body: some View {
    let day = model.butler
    let rows = day.sorted
    Group {
      VStack(alignment: .leading, spacing: 12) {
        HStack(alignment: .firstTextBaseline) {
          Text(model.store.butlerName).font(Font2.ui(22, .semibold)).foregroundStyle(pal.text)
          Text(F.dateShort(nowMs()) + " · " + L("看了 %@ 件，说了 %@ 件", "\(day.looked)", "\(rows.count)")).font(Font2.ui(12.5)).foregroundStyle(pal.text3)
          Spacer()
          Text(L("打断 %@ / 1 · 浮层 %@ / 3", "\(day.state?.notify ?? 0)", "\(day.state?.overlay ?? 0)")).font(Font2.num(11.5)).foregroundStyle(pal.text3)
        }
        if rows.isEmpty {
          VStack(alignment: .leading, spacing: 4) {
            Text(L("今天没什么要说的。")).font(Font2.ui(15, .medium)).foregroundStyle(pal.text)
            Text(L("已经替你看了 %@ 件事，都觉得不值得打断你。", "\(day.looked)")).font(Font2.ui(12.5)).foregroundStyle(pal.text3)
          }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(RoundedRectangle(cornerRadius: 14).fill(pal.fill))
        }
        ForEach(rows.filter { $0.level == "notify" }, id: \.id) { c in card(c, now: true) }
        section(L("等你呼出浮层才看到"), rows.filter { $0.level == "overlay" })
        section(L("其它"), rows.filter { $0.level == "desk" }, dim: true)
        if !day.notes.isEmpty {
          Text(day.notes.joined(separator: "\n")).font(Font2.ui(11)).foregroundStyle(pal.text3)
        }
      }
    }
  }

  @ViewBuilder private func section(_ title: String, _ list: [Candidate], dim: Bool = false) -> some View {
    if !list.isEmpty {
      Text(title).font(Font2.ui(12, .semibold)).foregroundStyle(pal.text3).padding(.top, 6)
      ForEach(list, id: \.id) { c in card(c, now: false).opacity(dim ? 0.75 : 1) }
    }
  }

  private func card(_ c: Candidate, now: Bool) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      if now { Text(L("现在")).font(Font2.ui(11, .semibold)).foregroundStyle(pal.accent) }
      Text(Brief.say(c)).font(Font2.ui(now ? 15 : 13.5, .medium)).foregroundStyle(pal.text).fixedSize(horizontal: false, vertical: true)
      HStack(spacing: 12) {
        if let a = c.action, a.type == "nav" { Button(a.label) { model.page = "market" }.buttonStyle(PillButton()) }
        if let a = c.action, a.type == "mail" {
          Button(a.label) { model.openURL(MailAPI.messageUrl(a.arg)) }.buttonStyle(PillButton())
        }
        link(L("晚点")) { model.snooze(c.id) }
        if !c.evidence.isEmpty { link(openEv.contains(c.id) ? L("收起证据") : L("证据")) { if openEv.contains(c.id) { openEv.remove(c.id) } else { openEv.insert(c.id) } } }
      }
      if openEv.contains(c.id) {
        Text(c.evidence.joined(separator: " · ")).font(Font2.ui(11.5)).foregroundStyle(pal.text2)
      }
    }
    .padding(now ? 16 : 12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(RoundedRectangle(cornerRadius: 14).fill(now ? pal.fill2 : pal.fill))
  }

  private func link(_ t: String, _ action: @escaping () -> Void) -> some View {
    Button(action: action) { Text(t).font(Font2.ui(12)).foregroundStyle(pal.text3) }.buttonStyle(.plain)
  }
}
