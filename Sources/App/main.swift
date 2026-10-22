// 桌面信息中心（原生版）入口。
import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  var model: DeskModel!
  var desks: [DeskWindow] = []
  var overlay: Overlay!
  var hotkey: HotKey!
  var console: ConsoleWindow!
  var notch = NotchWindow()
  var onboarding: OnboardingWindow!

  func applicationDidFinishLaunching(_ note: Notification) {
    log("start")
    model = DeskModel(store: Store())
    layoutDesks()
    overlay = Overlay(model: model)
    console = ConsoleWindow(model: model)
    overlay.openConsole = { [weak self] c in self?.console.show(chat: c) }
    overlay.onVisible = { [weak self] v in guard let self else { return }; self.notch.overlay(v, lyrics: self.lyricsOn) }
    buildMenu()
    model.start()
    applyNotch()
    model.onKeys = { [weak self] keys in
      guard let self else { return }
      if keys.contains("hotkey") { self.registerHotkey() }
      if keys.contains("notch") || keys.contains("lyrics") { self.applyNotch() }
      if keys.contains("screens") { self.layoutDesks() }
    }

    onboarding = OnboardingWindow(model: model)
    NotificationCenter.default.addObserver(forName: .showOnboarding, object: nil, queue: .main) { [weak self] _ in
      MainActor.assumeIsolated { self?.overlay.hide(restore: false); self?.onboarding.show() }
    }
    if !model.store.onboarded && !measuring { onboarding.show() }
    hotkey = HotKey { [weak self] in self?.overlay.toggle() }
    if !measuring { askAboutOldVersion() }
    registerHotkey()

    let ws = NSWorkspace.shared.notificationCenter
    // 锁屏、睡眠时暂停请求，省电；回来时马上刷新一次
    for n in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification] {
      ws.addObserver(forName: n, object: nil, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.model.pause(); self?.notch.pause() } }
    }
    for n in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
      ws.addObserver(forName: n, object: nil, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.model.resume(); self?.notch.resume() } }
    }
    let dn = DistributedNotificationCenter.default()
    dn.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.model.pause(); self?.notch.pause() } }
    dn.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.model.resume(); self?.notch.resume() } }
    NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
      MainActor.assumeIsolated { self?.layoutDesks() }
    }
  }

  /** 每块屏一层桌面（设置里选「只铺主屏」就只有一层）。接拔显示器、改分辨率时重新铺 */
  func layoutDesks() {
    for d in desks { d.close() }
    let all = model.store.data["screens"] as? String == "all"
    desks = (all ? NSScreen.screens : [mainScreen()]).map { DeskWindow(model: model, screen: $0) }
  }

  private var lyricsOn: Bool { (model.store.data["lyrics"] as? Bool) != false }
  private func applyNotch() { notch.setEnabled((model.store.data["notch"] as? Bool) != false, lyrics: lyricsOn) }

  /** 快捷键被别的程序占着（比如旧版还开着）就隔一会儿再试 */
  private func registerHotkey(attempt: Int = 0) {
    let acc = model.store.hotkey
    let ok = hotkey.register(acc)
    log("register \(acc) -> \(ok)")
    if !ok && attempt < 12 {
      DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in self?.registerHotkey(attempt: attempt + 1) }
    }
  }

  /** 旧版（Electron）和原生版同时开会出现两层桌面、抢同一个快捷键：问一次要不要退出旧版 */
  private func askAboutOldVersion() {
    let old = NSRunningApplication.runningApplications(withBundleIdentifier: "com.qianshengyue.desktophub")
    guard !old.isEmpty else { return }
    let a = NSAlert()
    a.messageText = "旧版桌面信息中心正在运行"
    a.informativeText = "两个版本同时开会出现两层桌面，快捷键也只能给一个。要退出旧版吗？（旧版的设置、布局、自选都在，原生版直接接着用）"
    a.addButton(withTitle: "退出旧版")
    a.addButton(withTitle: "都留着")
    NSApp.activate(ignoringOtherApps: true)
    if a.runModal() == .alertFirstButtonReturn { for app in old { app.terminate() } }
  }

  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    overlay.show()
    return false
  }

  private func buildMenu() {
    let main = NSMenu()
    let appItem = NSMenuItem()
    let appMenu = NSMenu()
    appMenu.addItem(withTitle: "关于桌面信息中心", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
    appMenu.addItem(.separator())
    appMenu.addItem(withTitle: "退出桌面信息中心", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    appItem.submenu = appMenu
    main.addItem(appItem)

    // 「编辑」菜单：输入框里的复制、粘贴、全选、撤销靠它（没有这个菜单，⌘C / ⌘V 不起作用）
    let editItem = NSMenuItem()
    let edit = NSMenu(title: L("编辑"))
    edit.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
    edit.addItem(withTitle: "重做", action: Selector(("redo:")), keyEquivalent: "Z")
    edit.addItem(.separator())
    edit.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
    edit.addItem(withTitle: "拷贝", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
    edit.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
    edit.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
    editItem.submenu = edit
    main.addItem(editItem)

    let viewItem = NSMenuItem()
    let view = NSMenu(title: L("显示"))
    view.addItem(item("呼出浮层", #selector(showOverlay), ""))
    view.addItem(item("管家", #selector(showButler), "1"))
    view.addItem(item("市场", #selector(showMarket), "2"))
    view.addItem(item("新闻", #selector(showNews), "3"))
    view.addItem(item("设置", #selector(showSettings), ","))
    view.addItem(.separator())
    view.addItem(item("应用和桌面", #selector(toggleLauncher), "e"))
    view.addItem(item("编辑桌面组件", #selector(editLayout), "l"))
    view.addItem(item("AI 总控台", #selector(showConsole), "0"))
    view.addItem(item("Muse（在浏览器里打开）", #selector(openMuse), ""))
    view.addItem(.separator())
    view.addItem(item("立即刷新全部数据", #selector(refreshAll), "r"))
    viewItem.submenu = view
    main.addItem(viewItem)
    NSApp.mainMenu = main
  }

  private func item(_ title: String, _ sel: Selector, _ key: String) -> NSMenuItem {
    let i = NSMenuItem(title: title, action: sel, keyEquivalent: key)
    i.target = self
    return i
  }

  @objc func showOverlay() { overlay.show(page: "home") }
  @objc func showButler() { overlay.show(page: "butler"); model.markSeen() }
  @objc func editLayout() { overlay.show(page: "home"); model.editing = true }
  @objc func refreshAll() { model.refreshAll() }
  @objc func showMarket() { overlay.show(page: "market") }
  @objc func showNews() { overlay.show(page: "news") }
  @objc func showSettings() { overlay.show(page: "settings") }
  @objc func toggleLauncher() {
    if !overlay.isVisible { overlay.show(page: "home") }
    NotificationCenter.default.post(name: .toggleLauncher, object: nil)
  }
  @objc func showConsole() { overlay.hide(restore: false); console.show() }
  @objc func openMuse() { model.openURL("https://muse.ai/") }
}

/** 测内存用：DESKHUB_MEASURE=1 时不问旧版、不读邮件（不弹自动化权限框） */
let measuring = ProcessInfo.processInfo.environment["DESKHUB_MEASURE"] == "1"

/** 日志：~/Library/Application Support/桌面信息中心/native.log（排查快捷键、启动问题用） */
func log(_ s: String) {
  let url = Store.defaultURL.deletingLastPathComponent().appendingPathComponent("native.log")
  let line = ISO8601DateFormatter().string(from: Date()) + " " + s + "\n"
  if let h = try? FileHandle(forWritingTo: url) {
    h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close()
  } else {
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? Data(line.utf8).write(to: url)
  }
}

let app = NSApplication.shared
if let i = CommandLine.arguments.firstIndex(of: "--snapshot") {
  app.setActivationPolicy(.prohibited)
  MainActor.assumeIsolated { Snapshot.run(Array(CommandLine.arguments[(i + 1)...])) }
  app.run()
} else {
  let delegate = MainActor.assumeIsolated { AppDelegate() }
  app.delegate = delegate
  app.setActivationPolicy(.regular)
  app.run()
}
