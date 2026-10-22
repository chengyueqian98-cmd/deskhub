// 设置页（改完立即生效）+ 提醒管理（在管家页下面，和旧版一样并在同一处）。
import SwiftUI
import ServiceManagement

struct SettingsPage: View {
  @Environment(\.pal) var pal
  @ObservedObject var model: DeskModel
  @State private var cityQ = ""
  @State private var cities: [(name: String, lat: Double, lon: Double, region: String)] = []
  @State private var key = ""
  @State private var keyStatus = ""
  @State private var hasKey = Keychain.hasKey
  @State private var loginOn = SMAppService.mainApp.status == .enabled
  @State private var mailPass = ""
  @State private var mailStatus = ""
  @State private var icsName = ""
  @State private var icsURL = ""

  var body: some View {
    let st = model.store
    VStack(alignment: .leading, spacing: 18) {
      PageHead(title: L("设置"), sub: L("改完立即生效")) { EmptyView() }

      section(L("桌面组件")) {
        ForEach(WIDGETS, id: \.id) { d in
          let on = model.layout.item(d.id)?.on == true
          row(d.name) { Toggle("", isOn: Binding(get: { on }, set: { model.toggleWidget(d.id, $0) })).toggleStyle(.switch).labelsHidden() }
        }
        HStack {
          Button(L("在桌面上拖动位置")) { model.page = "home"; model.editing = true }.buttonStyle(PillButton())
          Note(text: L("位置和大小都在浮层里调：拖动组件挪位置，点组件底部的「小 / 中 / 大」换大小。桌面那一层系统不接收鼠标，所以只能这样。"))
        }.padding(.top, 6)
      }

      section(L("外观")) {
        row(L("语言")) { seg("lang", st.lang, [("zh", "简体中文"), ("en", "English")]) }
        row(L("强调色")) {
          HStack(spacing: 8) {
            ForEach(ACCENTS, id: \.id) { a in
              Button { model.setTheme(["accent": a.id]) } label: {
                Circle().fill(Color(hex: a.dark)).frame(width: 20, height: 20)
                  .overlay(Circle().strokeBorder(.white, lineWidth: model.theme.accent == a.id ? 2 : 0))
              }.buttonStyle(.plain).help(L(a.name))
            }
          }
        }
        row(L("字号")) { themeSeg("scale", jsNum(model.theme.scale), [("0.9", "小"), ("1", "标准"), ("1.15", "大")]) }
        row(L("两侧渐隐")) { themeSeg("veil", jsNum(model.theme.veil), [("0", "无"), ("0.6", "淡"), ("1", "标准"), ("1.4", "浓")]) }
        row(L("组件风格")) { themeSeg("style", model.theme.cards ? "cards" : "lines", [("lines", "线条（无底色）"), ("cards", "卡片")]) }
        row(L("显示器")) {
          seg("screens", st.data["screens"] as? String == "all" ? "all" : "main", [("main", "只铺主屏"), ("all", "每块屏都铺")])
          Note(text: L("每块屏一套布局；浮层会开在鼠标所在的那块屏，在那里编辑的就是那块屏的布局"))
        }
        row("版本") {
          Text("\(DeskModel.currentVersion)").font(Font2.num(12.5)).foregroundStyle(pal.text2)
          Button(L("检查更新")) { Task { await model.checkUpdate(manual: true) } }.buttonStyle(MiniButton())
          if let u = model.update {
            Button(L("去下载 %@", u.version)) { model.openURL(u.page) }.buttonStyle(PillButton())
            Button(L("跳过这个版本")) { model.skipUpdate() }.buttonStyle(MiniButton())
          }
          Text(model.updateStatus).font(Font2.ui(12)).foregroundStyle(pal.text3)
        }
        row(L("首次引导")) { Button(L("重新打开")) { NotificationCenter.default.post(name: .showOnboarding, object: nil) }.buttonStyle(MiniButton()) }
      }

      section(L("管家")) {
        row(L("名字")) {
          CommitField(placeholder: L("管家"), value: st.butlerName, width: 200, numeric: false) { model.store.set(["butlerName": $0.trimmed().isEmpty ? L("管家") : String($0.trimmed().prefix(20))]) }
          Note(text: L("它在你桌面上的自称，页面标题和小组件都跟着改"))
        }
        row(L("重要的人")) {
          CommitField(placeholder: L("老师的名字、公司域名、关键词…"), value: st.mailRules.contacts.joined(separator: ", "), width: 360, numeric: false) { v in
            setRules(["contacts": v.components(separatedBy: CharacterSet(charactersIn: ",，")).map { $0.trimmed() }.filter { !$0.isEmpty }])
          }
          Note(text: L("发件人或主题里有这些字的未读邮件，管家会当成「有人在等你」"))
        }
        row(L("银行和账单")) {
          Toggle("", isOn: Binding(get: { st.mailRules.money }, set: { setRules(["money": $0]) })).toggleStyle(.switch).labelsHidden()
          Note(text: L("转账、账单、银行来信排进简报；出现欺诈、冻结等字眼会马上提醒"))
        }
        row(L("AI 判断重要邮件")) {
          Toggle("", isOn: Binding(get: { st.aiMail }, set: { setRules(["aiMail": $0]) })).toggleStyle(.switch).labelsHidden()
          Note(text: L("让 DeepSeek 看新邮件的发件人和主题（不看正文），挑出需要你处理的。要先填 DeepSeek 的 Key"))
        }
      }

      section("邮件") { mailSection }

      section("日程") { calendarSection }

      section(L("行情与观感")) {
        row(L("天气城市")) {
          VStack(alignment: .leading, spacing: 6) {
            HStack {
              TextField(L("输入城市名，比如 上海、East Lansing"), text: $cityQ).textFieldStyle(.roundedBorder).frame(width: 260).onSubmit(searchCity)
              Button(L("搜索"), action: searchCity).buttonStyle(MiniButton())
              Text(L("现在：") + st.city.name).font(Font2.ui(12)).foregroundStyle(pal.text3)
            }
            HStack { ForEach(Array(cities.enumerated()), id: \.offset) { _, c in
              Button("\(c.name) \(c.region)") {
                model.store.set(["city": ["name": c.name, "lat": c.lat, "lon": c.lon]])
                cities = []
                model.toast = L("已切换到 ") + c.name
              }.buttonStyle(MiniButton())
            } }
          }
        }
        row(L("涨跌颜色")) { seg("colors", st.colors, [("mono", "中性（▲ ▼）"), ("rup", "红涨绿跌"), ("gup", "绿涨红跌")]) }
        row(L("呼出快捷键")) { seg("hotkey", st.hotkey, [("Control+Alt+Space", "⌃⌥空格"), ("Command+Shift+Space", "⌘⇧空格"), ("Control+Alt+D", "⌃⌥D")]) }
        row(L("刘海")) { seg("notch", (st.data["notch"] as? Bool) == false ? "false" : "true", [("true", "显示 CPU / 内存"), ("false", "关闭")], bool: true) }
        row(L("歌词")) { seg("lyrics", (st.data["lyrics"] as? Bool) == false ? "false" : "true", [("true", "Apple Music 放歌时显示"), ("false", "关闭")], bool: true) }
        row(L("开机自动打开")) {
          Toggle("", isOn: Binding(get: { loginOn }, set: { on in
            do { if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } } catch { model.toast = L("设置失败：") + error.localizedDescription }
            loginOn = SMAppService.mainApp.status == .enabled
          })).toggleStyle(.switch).labelsHidden()
          Note(text: L("登录 Mac 后自动显示一瞥"))
        }
      }

      section(L("AI 与数据源")) {
        row(L("桌面 AI")) { seg("aiAgent", model.aiAgent, [("deepseek", "DeepSeek"), ("claude", "Claude Code")]) }
        row(L("提醒用的 AI")) { seg("reminderAgent", model.reminderAgent, [("deepseek", "DeepSeek"), ("claude", "Claude Code")]) }
        row(L("管家办事")) {
          Toggle("", isOn: Binding(get: { model.nlActions }, set: { model.store.set(["nlActions": $0]) })).toggleStyle(.switch).labelsHidden()
          Note(text: L("对管家说「把腾讯加进自选」「明早 8 点提醒我交作业」，它会列出要做的事，你点了「执行」才做；只能做软件内部的事，不下单、不发邮件、不改日历"))
        }
        row("DeepSeek") {
          VStack(alignment: .leading, spacing: 6) {
            HStack {
              SecureField(hasKey ? L("已保存（想换就重新粘贴）") : L("粘贴你的 API Key（sk-…）"), text: $key).textFieldStyle(.roundedBorder).frame(width: 300)
              Button(L("保存"), action: saveKey).buttonStyle(MiniButton())
              Button(L("测试")) { Task { keyStatus = L("正在测试…"); keyStatus = await DeepSeek.test(model: model.deepseekModel).map { "✗ " + $0 } ?? L("✓ 连通，Key 可用") } }.buttonStyle(MiniButton()).disabled(!hasKey)
              Button(L("清除")) { Keychain.clear(); hasKey = false; keyStatus = ""; model.toast = L("已清除 DeepSeek 的 Key") }.buttonStyle(MiniButton()).disabled(!hasKey)
            }
            Text(keyStatus.isEmpty ? (hasKey ? L("✓ 已保存在系统钥匙串里，只存在这台电脑上") : L("还没有 Key。去 platform.deepseek.com 创建一个，自己粘贴在这里——不要发给任何人，也不要发给 AI。")) : keyStatus)
              .font(Font2.ui(12)).foregroundStyle(pal.text3)
            seg("deepseekModel", model.deepseekModel, DeepSeek.models.map { ($0.0, $0.1) })
          }
        }
        row("Claude Code") {
          Note(text: ClaudeCLI.path.map { L("用本机的命令行：%@。没登录的话先在终端运行 claude 按提示登录。", $0) } ?? L("没找到 claude 命令行；装好 Claude Code 后就能用。"))
        }
        row(L("新闻来源")) {
          VStack(alignment: .leading, spacing: 6) {
            FlowRow(News.sources.map { s in (s.id, s.name) }) { id, name in
              Button(name) {
                let cur = st.newsSources
                model.store.set(["newsSources": cur.contains(id) ? cur.filter { $0 != id } : cur + [id]])
              }.buttonStyle(ChipStyle(on: st.newsSources.contains(id)))
            }
            Note(text: L("点一下开关；英文来源的标题是英文。改完几秒后新闻页和桌面更新"))
          }
        }
        row(L("量化系统")) {
          CommitField(placeholder: "", value: st.quantDir, width: 420, numeric: false) { model.store.set(["quantDir": $0.trimmed()]); Task { await model.refreshQuant() } }
          Button(L("选择…")) {
            let p = NSOpenPanel()
            p.canChooseDirectories = true; p.canChooseFiles = false
            if p.runModal() == .OK, let u = p.url { model.store.set(["quantDir": u.path]); Task { await model.refreshQuant() } }
          }.buttonStyle(MiniButton())
        }
      }

      section(L("数据与权限")) {
        Note(text: """
        行情：新浪财经公开接口，免费、延迟，不保证准确，只做展示和提醒。新闻：公开 RSS。天气：Open-Meteo。都不需要账号。
        日历：读 Mac「日历」App 里的日程。只读，不改。权限在「系统设置 → 隐私与安全性 → 日历」。
        邮件：读 Mac「邮件」App 的未读邮件。平时只取发件人、主题、时间；只有你点开某一封、或让管家概括时，才会读那几封的正文，正文会发给你在上面选的那个 AI。不发送、不删除、不标已读。「邮件」App 要开着。权限在「系统设置 → 隐私与安全性 → 自动化」。
        量化系统：只读它写出的文件，不启动、不修改、不下单。
        DeepSeek 的 Key 存在系统钥匙串里，不进设置文件、不进日志。
        """)
      }
    }
  }

  private func section<C: View>(_ title: String, @ViewBuilder _ c: () -> C) -> some View {
    let inner = c()
    return VStack(alignment: .leading, spacing: 8) {
      Text(L(title)).font(Font2.ui(14, .semibold)).foregroundStyle(pal.text)
      Panel { VStack(alignment: .leading, spacing: 10) { inner } }
    }
  }

  private func row<C: View>(_ label: String, @ViewBuilder _ c: () -> C) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 14) {
      Text(L(label)).font(Font2.ui(12.5)).foregroundStyle(pal.text2).frame(width: 110, alignment: .leading)
      c()
      Spacer(minLength: 0)
    }
  }

  private func seg(_ key: String, _ value: String, _ opts: [(String, String)], bool: Bool = false) -> some View {
    HStack(spacing: 2) {
      ForEach(opts, id: \.0) { v, n in
        Button {
          model.store.set([key: bool ? (v == "true") as Any : v as Any])
          if key == "aiAgent" { model.newOverlayChat() }
        } label: {
          Text(L(n)).font(Font2.ui(12, .medium)).foregroundStyle(v == value ? pal.text : pal.text2)
            .padding(.horizontal, 12).padding(.vertical, 4).background(Capsule().fill(v == value ? pal.fill2 : .clear))
        }.buttonStyle(.plain)
      }
    }.padding(2).background(Capsule().fill(pal.fill))
  }

  // —— 邮件：「邮件」App / IMAP 邮箱（Gmail、iCloud、Outlook、QQ、163…）/ 不读 ——
  private var mailCfg: JSON { model.store.data["mail"] as? JSON ?? [:] }
  private func setMail(_ patch: JSON) {
    var m = mailCfg
    for (k, v) in patch { m[k] = v }
    model.store.set(["mail": m])
  }

  @ViewBuilder private var mailSection: some View {
    let src = model.mailSource
    row("来源") {
      HStack(spacing: 2) {
        ForEach([("apple", "「邮件」App"), ("imap", "IMAP 邮箱"), ("off", "不读邮件")], id: \.0) { v, n in
          Button { setMail(["source": v]) } label: {
            Text(L(n)).font(Font2.ui(12, .medium)).foregroundStyle(v == src ? pal.text : pal.text2)
              .padding(.horizontal, 12).padding(.vertical, 4).background(Capsule().fill(v == src ? pal.fill2 : .clear))
          }.buttonStyle(.plain)
        }
      }.padding(2).background(Capsule().fill(pal.fill))
    }
    if src == "imap" {
      let email = mailCfg["email"] as? String ?? ""
      let p = IMAPProviders.by(mailCfg["provider"] as? String ?? IMAPProviders.guess(email))
      row("邮箱地址") {
        CommitField(placeholder: "you@gmail.com", value: email, width: 260, numeric: false) { v in
          setMail(["email": v.trimmed(), "provider": IMAPProviders.guess(v.trimmed())])
        }
      }
      row("服务商") {
        FlowRow(IMAPProviders.all.map { ($0.id, $0.name) }) { id, n in
          Button(L(n)) { setMail(["provider": id]) }.buttonStyle(ChipStyle(on: p.id == id))
        }
      }
      if p.id == "custom" {
        row("服务器") {
          CommitField(placeholder: "imap.example.com", value: mailCfg["host"] as? String ?? "", width: 220, numeric: false) { setMail(["host": $0.trimmed()]) }
          CommitField(placeholder: "993", value: num(mailCfg["port"]).map(jsNum) ?? "993", width: 60) { setMail(["port": Double($0) ?? 993]) }
        }
      }
      row("应用专用密码") {
        VStack(alignment: .leading, spacing: 6) {
          HStack {
            SecureField(Keychain.read(service: IMAPMail.keychainService, account: email) != nil ? L("已保存（想换就重新粘贴）") : L("粘贴应用专用密码 / 授权码"), text: $mailPass)
              .textFieldStyle(.roundedBorder).frame(width: 260)
            Button(L("保存")) {
              guard !email.isEmpty, !mailPass.isEmpty else { mailStatus = L("先填邮箱地址和密码"); return }
              mailStatus = Keychain.save(mailPass.trimmed(), service: IMAPMail.keychainService, account: email) ? L("已保存") : L("✗ 存进钥匙串失败")
              mailPass = ""
              model.kick("mail")
            }.buttonStyle(MiniButton())
            Button(L("测试连接")) {
              guard let a = IMAPMail.account(model.store) else { mailStatus = L("先填邮箱地址"); return }
              mailStatus = L("正在测试…")
              Task { mailStatus = await IMAPMail.test(a).map { "✗ " + $0 } ?? L("✓ 连通了，能读到收件箱") }
            }.buttonStyle(MiniButton())
            if !p.help.isEmpty { Button(L("怎么生成 ›")) { model.openURL(p.help) }.buttonStyle(MiniButton()) }
          }
          Text(mailStatus.isEmpty ? L("不是网页登录密码：Gmail、iCloud、Outlook、Yahoo 叫「应用专用密码」，QQ、163 叫「授权码」，要先在邮箱网站上打开 IMAP 再生成。密码只存在这台电脑的钥匙串里。") : mailStatus)
            .font(Font2.ui(12)).foregroundStyle(pal.text3).fixedSize(horizontal: false, vertical: true)
        }
      }
    }
    Note(text: L("只读：只取发件人、主题、时间；你点开某一封或让管家概括时才读那一封的正文。不发送、不删除、不标已读。"))
  }

  // —— 日程：系统日历（挑显示哪几个）+ 订阅链接 + 提前多久提醒 + 一周从哪天开始 ——
  @ViewBuilder private var calendarSection: some View {
    let cs = model.calendarSettings
    row("系统日历") {
      Toggle("", isOn: Binding(get: { cs.apple }, set: { model.setCalendarSettings(["apple": $0]) })).toggleStyle(.switch).labelsHidden()
      Note(text: L("读 Mac「日历」App 里的日程（包括你在里面登录的 Google、Outlook、iCloud 账户）"))
    }
    if cs.apple && Fetch.calendarStatus() == 3 {
      row("显示哪些") {
        FlowRow(Fetch.eventStore.calendars(for: .event).map { ($0.calendarIdentifier, $0.title) }) { id, n in
          Button(n) {
            var h = cs.hidden
            if h.contains(id) { h.remove(id) } else { h.insert(id) }
            model.setCalendarSettings(["hidden": Array(h)])
          }.buttonStyle(ChipStyle(on: !cs.hidden.contains(id)))
        }
      }
    }
    row("订阅链接") {
      VStack(alignment: .leading, spacing: 6) {
        ForEach(Array(cs.ics.enumerated()), id: \.offset) { i, f in
          HStack {
            Text(f.name.isEmpty ? f.url : f.name).font(Font2.ui(12.5)).foregroundStyle(pal.text).lineLimit(1).truncationMode(.middle).frame(maxWidth: 360, alignment: .leading)
            Button(L("删除")) {
              var list = model.store.data["calendarSettings"].flatMap { ($0 as? JSON)?["ics"] as? [JSON] } ?? []
              if i < list.count { list.remove(at: i) }
              model.setCalendarSettings(["ics": list])
            }.buttonStyle(MiniButton())
          }
        }
        HStack {
          TextField(L("名字（可不填）"), text: $icsName).textFieldStyle(.roundedBorder).frame(width: 120)
          TextField(L("https://… 或 webcal://… 的 .ics 地址"), text: $icsURL).textFieldStyle(.roundedBorder).frame(width: 300)
          Button(L("添加")) {
            guard ICS.url(icsURL) != nil, !icsURL.trimmed().isEmpty else { return }
            let list = (model.store.data["calendarSettings"].flatMap { ($0 as? JSON)?["ics"] as? [JSON] } ?? []) + [["name": icsName.trimmed(), "url": icsURL.trimmed()]]
            model.setCalendarSettings(["ics": list])
            icsName = ""; icsURL = ""
          }.buttonStyle(MiniButton())
        }
        Note(text: L("Google 日历：设置 → 某个日历 → 「iCal 格式的私密地址」；Outlook：设置 → 日历 → 共享的日历 → 发布 → ICS 链接。Windows 版用的也是这种链接。"))
      }
    }
    row("提前提醒") {
      HStack(spacing: 2) {
        ForEach([(0.0, "不提醒"), (5, "5 分钟"), (10, "10 分钟"), (20, "20 分钟"), (30, "30 分钟")], id: \.0) { v, n in
          Button { model.setCalendarSettings(["soonMin": v]) } label: {
            Text(L(n)).font(Font2.ui(12, .medium)).foregroundStyle(v == cs.soonMin ? pal.text : pal.text2)
              .padding(.horizontal, 12).padding(.vertical, 4).background(Capsule().fill(v == cs.soonMin ? pal.fill2 : .clear))
          }.buttonStyle(.plain)
        }
      }.padding(2).background(Capsule().fill(pal.fill))
      Note(text: L("日程快开始时管家说一声"))
    }
    row("每周开始于") {
      HStack(spacing: 2) {
        ForEach([(1, "周一"), (7, "周日")], id: \.0) { v, n in
          Button { model.setCalendarSettings(["weekStart": v]) } label: {
            Text(L(n)).font(Font2.ui(12, .medium)).foregroundStyle(v == cs.weekStart ? pal.text : pal.text2)
              .padding(.horizontal, 12).padding(.vertical, 4).background(Capsule().fill(v == cs.weekStart ? pal.fill2 : .clear))
          }.buttonStyle(.plain)
        }
      }.padding(2).background(Capsule().fill(pal.fill))
    }
  }

  private func setRules(_ patch: JSON) {
    var r = model.store.data["butlerRules"] as? JSON ?? [:]
    for (k, v) in patch { r[k] = v }
    model.store.set(["butlerRules": r])
  }

  private func themeSeg(_ key: String, _ value: String, _ opts: [(String, String)]) -> some View {
    HStack(spacing: 2) {
      ForEach(opts, id: \.0) { v, n in
        Button { model.setTheme([key: key == "style" ? v as Any : (Double(v) ?? 1) as Any]) } label: {
          Text(L(n)).font(Font2.ui(12, .medium)).foregroundStyle(v == value ? pal.text : pal.text2)
            .padding(.horizontal, 12).padding(.vertical, 4).background(Capsule().fill(v == value ? pal.fill2 : .clear))
        }.buttonStyle(.plain)
      }
    }.padding(2).background(Capsule().fill(pal.fill))
  }

  private func searchCity() {
    let q = cityQ.trimmed()
    guard !q.isEmpty else { return }
    Task {
      cities = await Fetch.searchCity(q)
      if cities.isEmpty { model.toast = L("没找到这个城市") }
    }
  }

  private func saveKey() {
    let k = key.trimmed()
    guard k.hasPrefix("sk-"), k.count >= 20, !k.contains(" ") else { keyStatus = L("✗ 这不像 DeepSeek 的 Key（应该以 sk- 开头）"); return }
    guard Keychain.save(k) else { keyStatus = L("✗ 存进钥匙串失败"); return }
    key = ""
    hasKey = true
    keyStatus = ""
    model.toast = L("已保存 DeepSeek 的 Key")
  }
}

/** 一行放不下就换行的按钮组 */
struct FlowRow<Content: View>: View {
  let items: [(String, String)]
  let content: (String, String) -> Content
  init(_ items: [(String, String)], @ViewBuilder content: @escaping (String, String) -> Content) { self.items = items; self.content = content }
  var body: some View {
    let rows = stride(from: 0, to: items.count, by: 5).map { Array(items[$0..<min($0 + 5, items.count)]) }
    VStack(alignment: .leading, spacing: 6) {
      ForEach(Array(rows.enumerated()), id: \.offset) { _, r in HStack(spacing: 6) { ForEach(r, id: \.0) { content($0.0, $0.1) } } }
    }
  }
}

// —— 提醒：AI 提醒的列表和编辑。到点由后台让 AI 跑，结果发通知、写在卡上 ——
struct RemindersSection: View {
  @Environment(\.pal) var pal
  @ObservedObject var model: DeskModel
  @State private var editing: JSON?

  var body: some View {
    let list = model.store.data["reminders"] as? [JSON] ?? []
    let agent = model.reminderAgent == "claude" ? "Claude Code" : "DeepSeek"
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .firstTextBaseline) {
        Text(L("提醒")).font(Font2.ui(16, .semibold)).foregroundStyle(pal.text)
        Text(L("到点后由 %@ 在后台整理，结果发系统通知 · 不写 AI 指令就是普通提醒", agent)).font(Font2.ui(12)).foregroundStyle(pal.text3)
        Spacer()
        Button(L("＋ 新提醒")) { editing = Reminders.new(time: "09:00", context: ["calendar": true, "mail": false, "market": false, "quant": false]).merging(["isNew": true]) { $1 } }.buttonStyle(PillButton())
      }
      if let e = editing { ReminderEditor(r: e, save: { save($0) }, cancel: { editing = nil }) }
      Panel {
        if list.isEmpty { Text(L("还没有提醒")).font(Font2.ui(12.5)).foregroundStyle(pal.text3) }
        ForEach(Array(list.enumerated()), id: \.offset) { i, r in card(r).overlay(alignment: .top) { if i > 0 { Rectangle().fill(pal.line).frame(height: 0.5) } } }
      }
      if editing == nil {
        Text(L("从模板开始")).font(Font2.ui(13, .semibold)).foregroundStyle(pal.text).padding(.top, 4)
        HStack(spacing: 10) {
          ForEach(Array(Reminders.templates.enumerated()), id: \.offset) { _, t in
            Button {
              editing = Reminders.new(title: t.title, time: t.time, days: t.days, prompt: t.prompt, context: t.context).merging(["isNew": true]) { $1 }
            } label: {
              VStack(alignment: .leading, spacing: 4) {
                Text(t.title).font(Font2.ui(13, .semibold)).foregroundStyle(pal.text)
                Text("\(t.time) · \(Actions.daysText(t.days))").font(Font2.ui(11.5)).foregroundStyle(pal.text3)
                Text(t.prompt.isEmpty ? L("普通提醒，不用 AI") : t.prompt).font(Font2.ui(11.5)).foregroundStyle(pal.text2).lineLimit(3).multilineTextAlignment(.leading)
              }.padding(12).frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading).background(RoundedRectangle(cornerRadius: 12).fill(pal.fill))
            }.buttonStyle(.plain)
          }
        }
      }
      Note(text: L("电脑睡眠时错过的提醒，醒来 2 小时内会补上，超过就跳过。AI 提醒会用掉少量 %@ 的额度。", agent))
    }
  }

  private func card(_ r: JSON) -> some View {
    let id = r["id"] as? String ?? ""
    let on = (r["enabled"] as? Bool) == true
    let prompt = r["prompt"] as? String ?? ""
    let days = Reminders.days(r)
    return HStack(alignment: .top, spacing: 14) {
      VStack(alignment: .leading, spacing: 2) {
        Text(r["time"] as? String ?? "").font(Font2.round(20, .medium)).foregroundStyle(on ? pal.text : pal.text3)
        Text(Actions.daysText(days)).font(Font2.ui(11)).foregroundStyle(pal.text3)
      }.frame(width: 70, alignment: .leading)
      VStack(alignment: .leading, spacing: 4) {
        Text((r["title"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? L("未命名提醒")).font(Font2.ui(13.5, .semibold)).foregroundStyle(on ? pal.text : pal.text3)
        Text(prompt.isEmpty ? L("普通提醒") : "AI: " + prompt).font(Font2.ui(12)).foregroundStyle(pal.text2).lineLimit(2)
        if (r["running"] as? Bool) == true { Text(L("AI 正在整理…")).font(Font2.ui(12)).foregroundStyle(pal.text3) }
        else if let e = r["lastError"] as? String { Text(L("上次出错（%@）：", F.rel(num(r["lastRunAt"]))) + e).font(Font2.ui(12)).foregroundStyle(pal.orange) }
        else if let res = r["lastResult"] as? String { Text("\(F.rel(num(r["lastRunAt"])))\n\(res)").font(Font2.ui(12)).foregroundStyle(pal.text2).textSelection(.enabled) }
        Text(on ? (Reminders.nextRun(r).map { L("下次：") + "\(F.dayLabel($0)) \(r["time"] as? String ?? "")" } ?? "") : L("已关闭")).font(Font2.ui(11.5)).foregroundStyle(pal.text3)
      }
      Spacer()
      HStack(spacing: 6) {
        Button(prompt.isEmpty ? L("试一下") : L("现在跑一次")) { model.toast = prompt.isEmpty ? L("已发通知") : L("已交给 AI，整理好会发通知"); model.runReminder(id) }.buttonStyle(MiniButton())
        Button(L("编辑")) { editing = r }.buttonStyle(MiniButton())
        Button(L("删除")) { model.store.set(["reminders": (model.store.data["reminders"] as? [JSON] ?? []).filter { $0["id"] as? String != id }]) }.buttonStyle(MiniButton())
        Toggle("", isOn: Binding(get: { on }, set: { model.patchReminder(id, ["enabled": $0]) })).toggleStyle(.switch).controlSize(.mini).labelsHidden()
      }
    }.padding(.vertical, 10)
  }

  private func save(_ r: JSON) {
    var x = r
    let isNew = x.removeValue(forKey: "isNew") != nil
    let all = model.store.data["reminders"] as? [JSON] ?? []
    let id = x["id"] as? String
    model.store.set(["reminders": isNew || !all.contains { $0["id"] as? String == id } ? all + [x] : all.map { $0["id"] as? String == id ? x : $0 }])
    editing = nil
    model.toast = isNew ? L("已添加提醒") : L("已保存")
  }
}

struct ReminderEditor: View {
  @Environment(\.pal) var pal
  @State var r: JSON
  let save: (JSON) -> Void
  let cancel: () -> Void
  @State private var title = ""
  @State private var time = Date()
  @State private var prompt = ""

  var body: some View {
    Panel {
      VStack(alignment: .leading, spacing: 10) {
        HStack { Text(L("标题")).frame(width: 80, alignment: .leading); TextField(L("比如：早间简报"), text: $title).textFieldStyle(.roundedBorder).frame(width: 260) }
        HStack {
          Text(L("时间")).frame(width: 80, alignment: .leading)
          DatePicker("", selection: $time, displayedComponents: .hourAndMinute).labelsHidden().frame(width: 90)
          ForEach(1...7, id: \.self) { d in
            let on = Reminders.days(r).contains(d)
            Button(F.weekHeads[d - 1]) {
              var ds = Reminders.days(r)
              if on { ds.removeAll { $0 == d } } else { ds.append(d); ds.sort() }
              r["days"] = ds
            }.buttonStyle(ChipStyle(on: on))
          }
          Text(L("不选 = 每天")).font(Font2.ui(11.5)).foregroundStyle(pal.text3)
        }
        HStack(alignment: .top) {
          Text(L("让 AI 做什么")).frame(width: 80, alignment: .leading)
          TextField(L("留空就是普通提醒。比如：总结今天的日程和未读邮件，提醒我最重要的事"), text: $prompt, axis: .vertical).textFieldStyle(.roundedBorder).lineLimit(2...4)
        }
        HStack {
          Text(L("附带的信息")).frame(width: 80, alignment: .leading)
          ForEach([("calendar", "日程"), ("mail", "未读邮件"), ("market", "自选行情"), ("quant", "量化账户")], id: \.0) { k, n0 in
            let n = L(n0)
            let ctx = r["context"] as? JSON ?? [:]
            let on = (ctx[k] as? Bool) == true
            Button(n) { var c = ctx; c[k] = !on; r["context"] = c }.buttonStyle(ChipStyle(on: on))
          }
        }
        HStack {
          Spacer().frame(width: 80)
          Button {
            guard !title.trimmed().isEmpty else { return }
            var x = r
            let c = Calendar.current.dateComponents([.hour, .minute], from: time)
            x["title"] = title.trimmed(); x["prompt"] = prompt.trimmed(); x["time"] = "\(pad2(c.hour ?? 8)):\(pad2(c.minute ?? 0))"
            save(x)
          } label: {
            Text(L("保存")).font(Font2.ui(12, .semibold)).foregroundStyle(.white).padding(.horizontal, 14).padding(.vertical, 5).background(Capsule().fill(pal.accent))
          }.buttonStyle(.plain)
          Button(L("取消"), action: cancel).buttonStyle(PillButton())
        }
      }.font(Font2.ui(12.5)).foregroundStyle(pal.text2)
    }
    .onAppear {
      title = r["title"] as? String ?? ""
      prompt = r["prompt"] as? String ?? ""
      let p = (r["time"] as? String ?? "08:00").components(separatedBy: ":").compactMap { Int($0) }
      time = Calendar.current.date(bySettingHour: p.first ?? 8, minute: p.count > 1 ? p[1] : 0, second: 0, of: Date()) ?? Date()
    }
  }
}
