// 离屏截图：不开窗口、不抢快捷键、不碰「邮件」（不会弹自动化权限框），用真实界面代码画一张 PNG。
//   DeskHub --snapshot out.png [light|dark] [desk|overlay|butler|edit] [W H]
// 行情、新闻、天气是真的去拿的；邮件用示例数据；日历有权限就读真的。改界面后用它看，别凭想象。
import AppKit
import SwiftUI

var isSnapshot = false

@MainActor
enum Snapshot {
  static var launcher: Bool? = nil
  static func run(_ args: [String]) {
    isSnapshot = true
    let out = args[safe: 0] ?? "snapshot.png"
    let dark = (args[safe: 1] ?? "dark") == "dark"
    let mode = args[safe: 2] ?? "desk"
    let W = Double(args[safe: 3] ?? "") ?? 1512, H = Double(args[safe: 4] ?? "") ?? 982
    // demo：一份全新的设置（不碰用户自己的 desk.json），用来截 README 和检查新组件
    let demo = ProcessInfo.processInfo.environment["DESKHUB_DEMO"]
    let store: Store
    if let demo {
      let url = FileManager.default.temporaryDirectory.appendingPathComponent("deskhub-demo-\(UUID().uuidString).json")
      store = Store(url: url)
      var L = normalize(presetLayout(demo == "minimal" ? "minimal" : "work"))
      if demo == "all" {
        for (id, col, row, size) in [("todo", 2, 0, "M"), ("countdown", 4, 0, "M"), ("crypto", 2, 1, "M"), ("github", 4, 1, "M"), ("rss", 2, 2, "L"), ("pomodoro", 4, 2, "S"), ("market", 5, 2, "S")] {
          L = toggle(L.json, id, true)
          L = move(L.json, id, col, row)
          L = setSize(L.json, id, size)
        }
      }
      let en = ProcessInfo.processInfo.environment["DESKHUB_LANG"] == "en"
      if en {
        store.set(["watch": ["gb_aapl", "gb_nvda", "gb_msft", "gb_tsla", "gb_inx", "gb_ixic", "rt_hk00700"], "newsSources": ["bbcbiz", "npr", "hn"]])
      }
      store.set(["onboarded": true, "lang": ProcessInfo.processInfo.environment["DESKHUB_LANG"] ?? "zh", "layout": L.json, "butlerName": en ? "Butler" : "管家",
                 "city": ["name": "Boston", "lat": 42.36, "lon": -71.06], "theme": ["style": ProcessInfo.processInfo.environment["DESKHUB_STYLE"] ?? "lines"],
                 "widgetConfig": ["countdown": ["items": [["title": en ? "Final exams" : "期末考试", "date": "2026-12-15"], ["title": en ? "Spring trip" : "春节", "date": "2027-02-06"]]],
                                  "crypto": ["coins": ["bitcoin", "ethereum", "solana"], "vs": "usd"], "github": ["repos": ["apple/swift"]],
                                  "rss": ["url": en ? "https://hnrss.org/frontpage" : "https://sspai.com/feed"], "worldclock": ["zones": ["Asia/Shanghai", "Europe/London"]]]])
    } else { store = Store() }
    appLang = store.lang
    let model = DeskModel(store: store)
    model.mail = MailState(ok: true, unread: 37, items: [
      MailItem(name: "School Registrar", email: "registrar@school.edu", subject: "Spring 2027 enrollment opens Monday", ts: nowMs() - 40 * 60e3, id: "a"),
      MailItem(name: "Bank of America", email: "alerts@bofa.com", subject: "Your statement is ready", ts: nowMs() - 3 * 3600e3, id: "b"),
      MailItem(name: "张老师", email: "zhang@example.com", subject: "下周组会改到周四", ts: nowMs() - 26 * 3600e3, id: "c"),
    ])
    Task {
      async let a: Void = model.refreshMarket()
      async let b: Void = model.refreshWeather()
      async let c: Void = model.refreshNews()
      async let d: Void = model.refreshQuant()
      async let e: Void = model.refreshBattery()
      _ = await (a, b, c, d, e)
      if demo != nil {
        await model.refreshCrypto(); await model.refreshRepos(); await model.refreshFeeds()
        // README 截图用示例待办和日程（不读用户自己的日历）
        let t = ymd(nowMs())
        let at = { (h: Int, m: Int) in localMs(t.y, t.m, t.d, h, m) }
        let en = appLang == "en"
        model.todos = TodoState(ok: true, items: [
          TodoItem(id: "1", title: en ? "Submit lab report" : "交实验报告", due: at(23, 0), list: "", listId: "", color: [106, 159, 216]),
          TodoItem(id: "2", title: en ? "Buy milk" : "买牛奶", due: nil, list: "", listId: "", color: [211, 160, 98]),
          TodoItem(id: "3", title: en ? "Call Mom" : "给妈妈打电话", due: at(20, 0) + 86400e3, list: "", listId: "", color: [90, 168, 130]),
        ])
        model.calendar = CalendarState(ok: true, events: [
          CalEvent(id: "a", title: en ? "Design review" : "设计评审", start: at(10, 0), end: at(11, 0), location: en ? "Room 3" : "3 号会议室", color: [106, 159, 216]),
          CalEvent(id: "b", title: en ? "Lunch with Alex" : "和小林吃午饭", start: at(12, 30), end: at(13, 30), color: [211, 160, 98]),
          CalEvent(id: "c", title: en ? "Gym" : "健身", start: at(18, 0), end: at(19, 0), color: [90, 168, 130]),
        ])
      }
      if demo == nil { model.refreshCalendar() }
      try? await Task.sleep(nanoseconds: 600_000_000)   // 等管家排完
      if mode == "edit" { model.editing = true }
      if ["butler", "market", "news", "settings"].contains(mode) { model.page = mode }
      if mode == "launcher" { Snapshot.launcher = true }
      if mode == "chat" {
        let c = model.overlayChat
        c.items = [TItem(kind: .user, text: "把腾讯加进自选，买入价记 350"),
                   TItem(kind: .ai, text: "好的，我先把**腾讯控股**加进自选，再记下你说的买入价 350。\n```actions\n[]\n```")]
        c.pending = PendingActions(list: Actions.checkAll([["do": "watch.add", "query": "腾讯"], ["do": "plan.set", "query": "腾讯", "buy": 350], ["do": "order.buy", "query": "腾讯"]]), withMail: true)
      }
      let insets = Insets(top: 33, left: 8, bottom: 8 + 70, right: 8)
      let view: AnyView
      if mode.hasPrefix("onboard") {
        view = AnyView(ZStack {
          wallpaper(W, H, dark: true).blur(radius: 30)
          OnboardingView(model: model, done: {}, startPage: Int(mode.dropFirst(7)) ?? 0)
            .background(RoundedRectangle(cornerRadius: 16).fill(Color(r: 30, g: 32, b: 38, a: 0.92)))
            .environment(\.pal, Palette.make(dark: true))
        }.environment(\.colorScheme, .dark))
      } else if mode == "desk" {
        view = AnyView(ZStack {
          wallpaper(W, H, dark: dark)
          DeskRoot(model: model, insets: insets)
        }.environment(\.colorScheme, dark ? .dark : .light))
      } else {
        view = AnyView(ZStack {
          wallpaper(W, H, dark: dark).blur(radius: 40)
          Color(r: 30, g: 32, b: 38, a: 0.72)
          OverlayRoot(model: model, insets: insets, close: {})
        })
      }
      let r = ImageRenderer(content: view.frame(width: W, height: H))
      r.scale = 2
      guard let img = r.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
            let png = rep.representation(using: .png, properties: [:]) else { print("截图失败"); exit(1) }
      try? png.write(to: URL(fileURLWithPath: out))
      print("已保存 \(out)")
      exit(0)
    }
  }

  /** 用户自己的壁纸（拿不到就用一张渐变代替） */
  static func wallpaper(_ W: Double, _ H: Double, dark: Bool) -> some View {
    // DESKHUB_NOWALL=1：README 截图不用用户自己的壁纸（版权、隐私），换成一张渐变
    let url = ProcessInfo.processInfo.environment["DESKHUB_NOWALL"] != nil ? nil : NSScreen.main.flatMap { NSWorkspace.shared.desktopImageURL(for: $0) }
    return Group {
      if let url, let img = NSImage(contentsOf: url) {
        Image(nsImage: img).resizable().aspectRatio(contentMode: .fill).frame(width: W, height: H).clipped()
      } else {
        LinearGradient(colors: dark ? [Color(hex: "#1b2740"), Color(hex: "#3a2c4a"), Color(hex: "#5a3a3a")] : [Color(hex: "#cfe0f5"), Color(hex: "#f3e3d3")], startPoint: .topLeading, endPoint: .bottomTrailing)
      }
    }
  }
}

/** 离屏截图画不出 ScrollView：截图时平铺，平时照常滚动 */
struct MaybeScroll<C: View>: View {
  @ViewBuilder var content: () -> C
  var body: some View {
    if isSnapshot { VStack(spacing: 0) { content(); Spacer(minLength: 0) } } else { ScrollView { content() } }
  }
}
