// 首次引导：像 Apple 的产品第一次打开那样，一页只讲一件事，大标题、一句说明、底部一个「继续」。
// 语言 → 欢迎 → 你是谁（决定默认放哪些组件）→ 城市 → 管家（名字、重要的人）→ 权限 → AI（可跳过）→ 完成。
// 每一步都能跳过；做完写 onboarded = true，以后不再出现（设置里可以重新打开）。
import SwiftUI
import AppKit
import EventKit

extension Notification.Name { static let showOnboarding = Notification.Name("deskhub.showOnboarding") }

@MainActor
final class OnboardingWindow: NSObject, NSWindowDelegate {
  private var window: NSWindow?
  private let model: DeskModel
  init(model: DeskModel) { self.model = model }

  func show() {
    if let w = window { w.makeKeyAndOrderFront(nil); return }
    let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 860, height: 620), styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
    w.titlebarAppearsTransparent = true
    w.titleVisibility = .hidden
    w.isMovableByWindowBackground = true
    w.isReleasedWhenClosed = false
    w.appearance = NSAppearance(named: .darkAqua)
    let fx = NSVisualEffectView()
    fx.material = .hudWindow
    fx.blendingMode = .behindWindow
    fx.state = .active
    let h = NSHostingView(rootView: OnboardingView(model: model, done: { [weak self] in self?.window?.close() }).environment(\.pal, Palette.make(dark: true)))
    h.translatesAutoresizingMaskIntoConstraints = false
    fx.addSubview(h)
    NSLayoutConstraint.activate([h.leadingAnchor.constraint(equalTo: fx.leadingAnchor), h.trailingAnchor.constraint(equalTo: fx.trailingAnchor),
                                 h.topAnchor.constraint(equalTo: fx.topAnchor), h.bottomAnchor.constraint(equalTo: fx.bottomAnchor)])
    w.contentView = fx
    w.center()
    w.delegate = self
    window = w
    NSApp.activate(ignoringOtherApps: true)
    w.makeKeyAndOrderFront(nil)
  }

  nonisolated func windowWillClose(_ notification: Notification) {
    MainActor.assumeIsolated {
      // 关掉窗口也算走完了（用户可以在设置里重新打开）
      if !model.store.onboarded { model.store.set(["onboarded": true]) }
      window?.contentView = nil
      window = nil
    }
  }
}

struct OnboardingView: View {
  @Environment(\.pal) var pal
  @ObservedObject var model: DeskModel
  let done: () -> Void
  @State private var page: Int
  @State private var lang = "zh"
  @State private var persona = "work"
  @State private var personaTouched = false   // 重新打开引导时，没点过身份就不动现有的布局
  @State private var cityQ = ""
  @State private var cities: [(name: String, lat: Double, lon: Double, region: String)] = []
  @State private var city: (name: String, lat: Double, lon: Double)?
  @State private var butler = ""
  @State private var contacts = ""
  @State private var key = ""
  @State private var calOK = Fetch.calendarStatus() == 3
  @State private var remOK = EKEventStore.authorizationStatus(for: .reminder) == .fullAccess
  @State private var shown = isSnapshot
  private let pages = 8

  init(model: DeskModel, done: @escaping () -> Void, startPage: Int = 0) {
    self.model = model
    self.done = done
    _page = State(initialValue: startPage)
  }

  var body: some View {
    VStack(spacing: 0) {
      ZStack {
        content.id("\(page)-\(lang)")
          .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .move(edge: .leading).combined(with: .opacity)))
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .padding(.horizontal, 70).padding(.top, 50)
      if page > 0 {
        HStack(spacing: 7) {
          ForEach(1..<pages, id: \.self) { i in Circle().fill(i == page ? pal.text : pal.text3.opacity(0.5)).frame(width: 6, height: 6) }
        }.padding(.bottom, 18)
        HStack {
          if page > 1 { Button(L("返回")) { go(page - 1) }.buttonStyle(.plain).font(Font2.ui(13)).foregroundStyle(pal.text2) }
          Spacer()
          if [3, 4, 5, 6].contains(page) { Button(L("跳过")) { go(page + 1) }.buttonStyle(.plain).font(Font2.ui(13)).foregroundStyle(pal.text2).padding(.trailing, 16) }
          Button { page == pages - 1 ? finish() : next() } label: {
            Text(page == pages - 1 ? L("开始使用") : L("继续")).font(Font2.ui(14, .semibold)).foregroundStyle(.white)
              .frame(width: 180, height: 38).background(Capsule().fill(pal.accent))
          }.buttonStyle(.plain).keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 40).padding(.bottom, 32)
      }
    }
    .frame(width: 860, height: 620)
    .foregroundStyle(pal.text)
    .onAppear {
      lang = model.store.lang
      appLang = lang
      butler = model.store.butlerName
      contacts = model.store.mailRules.contacts.joined(separator: ", ")
      withAnimation(.easeOut(duration: 0.8).delay(0.1)) { shown = true }
    }
  }

  private func go(_ p: Int) { withAnimation(.spring(response: 0.45, dampingFraction: 0.9)) { page = max(0, min(pages - 1, p)) } }
  private func next() {
    if page == 4 { saveButler() }
    if page == 6 { saveKey() }
    go(page + 1)
  }

  private func title(_ t: String, _ sub: String) -> some View {
    VStack(spacing: 12) {
      Text(t).font(.system(size: 34, weight: .bold)).multilineTextAlignment(.center)
      Text(sub).font(Font2.ui(15)).foregroundStyle(pal.text2).multilineTextAlignment(.center).lineSpacing(3).frame(maxWidth: 540)
    }
  }

  @ViewBuilder private var content: some View {
    switch page {
    case 0: language
    case 1: welcome
    case 2: personaPage
    case 3: cityPage
    case 4: butlerPage
    case 5: permissions
    case 6: aiPage
    default: finishPage
    }
  }

  // —— 0 语言 ——
  private var language: some View {
    VStack(spacing: 36) {
      Spacer()
      VStack(spacing: 6) {
        Text("你好").font(.system(size: 64, weight: .bold, design: .rounded))
        Text("Hello").font(.system(size: 64, weight: .bold, design: .rounded)).foregroundStyle(pal.text2)
      }
      .opacity(shown ? 1 : 0).scaleEffect(shown ? 1 : 0.92)
      HStack(spacing: 16) {
        ForEach([("zh", "简体中文"), ("en", "English")], id: \.0) { id, name in
          Button {
            lang = id
            appLang = id
            model.store.set(["lang": id])
            if model.store.data["butlerName"] == nil { butler = id == "en" ? "Butler" : "管家" }
            go(1)
          } label: {
            Text(name).font(Font2.ui(16, .semibold)).frame(width: 200, height: 52)
              .background(RoundedRectangle(cornerRadius: 14).fill(pal.fill2))
          }.buttonStyle(.plain)
        }
      }
      Spacer()
    }
  }

  // —— 1 欢迎 ——
  private var welcome: some View {
    VStack(spacing: 34) {
      Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 96, height: 96)
      title(L("桌面信息中心"), L("一个只在重要时刻说话的桌面。"))
      VStack(alignment: .leading, spacing: 20) {
        feature("rectangle.split.3x1", L("桌面上一眼看全"), L("时钟、天气、日程、行情、邮件安静地放在壁纸两侧，中间留给你。"))
        feature("sparkle", L("管家只说重要的事"), L("有人在等你回、日程快开始了、到了你设的价——才会提醒你。"))
        feature("command", L("随时呼出"), L("按 ⌃⌥空格 打开可以操作的那一层：问问题、改布局、看详情。"))
      }.frame(maxWidth: 520)
    }
  }

  private func feature(_ icon: String, _ t: String, _ d: String) -> some View {
    HStack(alignment: .top, spacing: 16) {
      Image(systemName: icon).font(.system(size: 22)).foregroundStyle(pal.accent).frame(width: 34)
      VStack(alignment: .leading, spacing: 3) {
        Text(t).font(Font2.ui(15, .semibold))
        Text(d).font(Font2.ui(13)).foregroundStyle(pal.text2).fixedSize(horizontal: false, vertical: true)
      }
    }
  }

  // —— 2 你是谁 ——
  private var personaPage: some View {
    VStack(spacing: 28) {
      title(L("你主要用电脑做什么？"), L("先帮你摆一套合适的组件，之后随时可以改。"))
      LazyVGrid(columns: [GridItem(.fixed(330)), GridItem(.fixed(330))], spacing: 14) {
        personaCard("student", "graduationcap", L("学生"), L("待办、日历、倒数日、天气"))
        personaCard("work", "briefcase", L("上班"), L("邮件、日历、世界时钟、天气"))
        personaCard("invest", "chart.line.uptrend.xyaxis", L("关注投资"), L("行情、新闻、加密货币、天气"))
        personaCard("minimal", "circle.dotted", L("极简"), L("只要时钟、天气和管家"))
      }
    }
  }

  private func personaCard(_ id: String, _ icon: String, _ t: String, _ d: String) -> some View {
    Button { persona = id; personaTouched = true } label: {
      HStack(spacing: 14) {
        Image(systemName: icon).font(.system(size: 22)).frame(width: 36).foregroundStyle(persona == id ? pal.accent : pal.text2)
        VStack(alignment: .leading, spacing: 3) {
          Text(t).font(Font2.ui(15, .semibold))
          Text(d).font(Font2.ui(12)).foregroundStyle(pal.text2)
        }
        Spacer()
        Image(systemName: persona == id ? "checkmark.circle.fill" : "circle").foregroundStyle(persona == id ? pal.accent : pal.text3)
      }
      .padding(16).frame(height: 76)
      .background(RoundedRectangle(cornerRadius: 14).fill(persona == id ? pal.fill2 : pal.fill))
      .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(persona == id ? pal.accent : .clear, lineWidth: 1.5))
    }.buttonStyle(.plain)
  }

  // —— 3 城市 ——
  private var cityPage: some View {
    VStack(spacing: 26) {
      Image(systemName: "cloud.sun.fill").symbolRenderingMode(.multicolor).font(.system(size: 54))
      title(L("你在哪个城市？"), L("用来显示天气。只用来查天气，不会上传到别处。"))
      HStack {
        TextField(L("输入城市名，比如 上海、Boston"), text: $cityQ).textFieldStyle(.plain).font(Font2.ui(15))
          .padding(.horizontal, 16).frame(height: 42).background(RoundedRectangle(cornerRadius: 12).fill(pal.fill2)).frame(width: 360)
          .onSubmit(searchCity)
        Button(L("搜索"), action: searchCity).buttonStyle(PillButton())
      }
      VStack(spacing: 6) {
        ForEach(Array(cities.prefix(5).enumerated()), id: \.offset) { _, c in
          Button { city = (c.name, c.lat, c.lon); model.store.set(["city": ["name": c.name, "lat": c.lat, "lon": c.lon]]); cities = [] } label: {
            HStack { Text(c.name).font(Font2.ui(14, .medium)); Text(c.region).font(Font2.ui(12)).foregroundStyle(pal.text3); Spacer() }
              .padding(.horizontal, 14).frame(width: 440, height: 36).background(RoundedRectangle(cornerRadius: 10).fill(pal.fill))
          }.buttonStyle(.plain)
        }
        if let city { Label(L("已选：") + city.name, systemImage: "checkmark.circle.fill").foregroundStyle(pal.green).font(Font2.ui(14)) }
      }
    }
  }

  private func searchCity() {
    let q = cityQ.trimmed()
    guard !q.isEmpty else { return }
    Task { cities = await Fetch.searchCity(q) }
  }

  // —— 4 管家 ——
  private var butlerPage: some View {
    VStack(spacing: 26) {
      Image(systemName: "sparkle").font(.system(size: 50)).foregroundStyle(pal.accent)
      title(L("认识一下你的管家"), L("它只在真正重要的时候出声：有人在等你回、日程快开始了、到了你设的价。"))
      VStack(alignment: .leading, spacing: 18) {
        labeled(L("给它起个名字")) {
          TextField(L("管家"), text: $butler).textFieldStyle(.plain).font(Font2.ui(15)).padding(.horizontal, 14).frame(height: 40)
            .background(RoundedRectangle(cornerRadius: 10).fill(pal.fill2))
        }
        labeled(L("谁的邮件对你最重要？（名字、邮箱、学校或公司的域名，用逗号分开）")) {
          TextField(L("比如：王老师, @mycompany.com, 面试"), text: $contacts).textFieldStyle(.plain).font(Font2.ui(15)).padding(.horizontal, 14).frame(height: 40)
            .background(RoundedRectangle(cornerRadius: 10).fill(pal.fill2))
        }
      }.frame(width: 520)
    }
  }

  private func labeled<C: View>(_ t: String, @ViewBuilder _ c: () -> C) -> some View {
    VStack(alignment: .leading, spacing: 8) { Text(t).font(Font2.ui(13)).foregroundStyle(pal.text2); c() }
  }

  private func saveButler() {
    let name = butler.trimmed()
    var r = model.store.data["butlerRules"] as? JSON ?? [:]
    r["contacts"] = contacts.components(separatedBy: CharacterSet(charactersIn: ",，")).map { $0.trimmed() }.filter { !$0.isEmpty }
    model.store.set(["butlerName": name.isEmpty ? L("管家") : String(name.prefix(20)), "butlerRules": r])
  }

  // —— 5 权限 ——
  private var permissions: some View {
    VStack(spacing: 26) {
      Image(systemName: "hand.raised.fill").font(.system(size: 48)).foregroundStyle(pal.accent)
      title(L("需要你允许的几件事"), L("都是只读的，数据只留在这台电脑上。不想给的可以跳过，对应的组件不显示内容就是了。"))
      VStack(spacing: 10) {
        permRow("calendar", L("日历"), L("在桌面上显示今天和接下来的日程"), ok: calOK) {
          Task { _ = try? await Fetch.eventStore.requestFullAccessToEvents(); calOK = Fetch.calendarStatus() == 3; model.refreshCalendar() }
        }
        permRow("checklist", L("提醒事项"), L("「待办」组件显示没完成的事"), ok: remOK) {
          Task { await model.askReminders(); remOK = EKEventStore.authorizationStatus(for: .reminder) == .fullAccess }
        }
        permRow("envelope", L("邮件"), L("打开「邮件」App 后，第一次读取时系统会问你"), ok: nil) {}
      }.frame(width: 560)
    }
  }

  private func permRow(_ icon: String, _ t: String, _ d: String, ok: Bool?, _ action: @escaping () -> Void) -> some View {
    HStack(spacing: 14) {
      Image(systemName: icon).font(.system(size: 18)).frame(width: 30).foregroundStyle(pal.text2)
      VStack(alignment: .leading, spacing: 2) { Text(t).font(Font2.ui(14, .semibold)); Text(d).font(Font2.ui(12)).foregroundStyle(pal.text2) }
      Spacer()
      if ok == true { Label(L("已允许"), systemImage: "checkmark.circle.fill").font(Font2.ui(12.5)).foregroundStyle(pal.green) }
      else if ok == false { Button(L("允许"), action: action).buttonStyle(PillButton()) }
    }
    .padding(.horizontal, 16).frame(height: 60).background(RoundedRectangle(cornerRadius: 12).fill(pal.fill))
  }

  // —— 6 AI ——
  private var aiPage: some View {
    VStack(spacing: 26) {
      Image(systemName: "bubble.left.and.text.bubble.right.fill").font(.system(size: 46)).foregroundStyle(pal.accent)
      title(L("想让管家能聊天、能办事吗？"), L("可选。填一个 DeepSeek 的 API Key（很便宜，自己在 platform.deepseek.com 申请），就能问它问题、让它帮你加自选、建提醒。Key 只存在这台电脑的钥匙串里。"))
      SecureField(L("粘贴 API Key（sk-…），不填也可以"), text: $key).textFieldStyle(.plain).font(Font2.ui(15))
        .padding(.horizontal, 16).frame(width: 440, height: 42).background(RoundedRectangle(cornerRadius: 12).fill(pal.fill2))
      if Keychain.hasKey { Label(L("已经有 Key 了"), systemImage: "checkmark.circle.fill").foregroundStyle(pal.green).font(Font2.ui(13)) }
      if ClaudeCLI.path != nil { Text(L("也检测到了 Claude Code，可以在设置里换成它。")).font(Font2.ui(12.5)).foregroundStyle(pal.text3) }
    }
  }

  private func saveKey() {
    let k = key.trimmed()
    if k.hasPrefix("sk-"), k.count >= 20, Keychain.save(k) {
      key = ""
      model.store.set(["aiAgent": "deepseek", "reminderAgent": "deepseek"])
      model.newOverlayChat()
    }
  }

  // —— 7 完成 ——
  private var finishPage: some View {
    VStack(spacing: 30) {
      Image(systemName: "checkmark.circle.fill").font(.system(size: 60)).foregroundStyle(pal.green)
      title(L("一切就绪"), L("桌面已经摆好了。想操作的时候，按下面这几个键："))
      HStack(spacing: 10) {
        ForEach(["⌃", "⌥", L("空格")], id: \.self) { k in
          Text(k).font(.system(size: 26, weight: .medium, design: .rounded)).frame(minWidth: 64, minHeight: 64).padding(.horizontal, 10)
            .background(RoundedRectangle(cornerRadius: 12).fill(pal.fill2)).overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(pal.line))
        }
      }
      Text(L("在浮层里长按任意组件可以挪位置、换大小、加新的组件。")).font(Font2.ui(13)).foregroundStyle(pal.text3)
    }
  }

  private func finish() {
    var patch: JSON = ["onboarded": true]
    if !model.store.onboarded || personaTouched { patch["preset"] = persona; patch["layout"] = presetLayout(persona) }
    if persona == "invest" && model.store.data["watch"] == nil { patch["watch"] = Market.defaultWatch }
    if persona == "student" || persona == "minimal" { patch["newsSources"] = News.defaultIds }
    model.store.set(patch)
    model.refreshAll()
    model.kickWidgets()
    done()
  }
}
