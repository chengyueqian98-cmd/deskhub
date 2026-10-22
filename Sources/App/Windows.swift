// 两个窗口：
//   桌面层：壁纸之上、桌面图标之下，铺满主屏，只显示（收不到鼠标键盘）
//   浮层：⌃⌥空格 呼出的全屏可操作版，深色磨砂；Esc / 再按快捷键收起并把焦点还给之前的软件；
//         失焦自动收起（不还焦点，否则会把用户切回别的桌面空间）；收起 3 分钟后销毁省内存，下次再建
import AppKit
import SwiftUI

/** 主屏幕（带菜单栏的那块）。浮层固定在主屏，不跟鼠标走——跟鼠标会出现在用户没在看的屏幕上 */
func mainScreen() -> NSScreen { NSScreen.screens.first ?? NSScreen.main! }

func insetsOf(_ s: NSScreen) -> Insets {
  let f = s.frame, v = s.visibleFrame
  return Insets(top: f.maxY - v.maxY, left: v.minX - f.minX + 8, bottom: v.minY - f.minY + 8, right: f.maxX - v.maxX + 8)
}

/** 显示器的名字当布局的键：主屏是 main，其它屏用系统给的名字（插拔之后还能对上） */
func screenKey(_ s: NSScreen) -> String { s == mainScreen() ? "main" : s.localizedName }

@MainActor
final class DeskWindow {
  let window: NSWindow
  private let model: DeskModel
  let screen: NSScreen

  init(model: DeskModel, screen: NSScreen = mainScreen()) {
    self.model = model
    self.screen = screen
    let s = screen
    window = NSWindow(contentRect: s.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
    window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
    window.ignoresMouseEvents = true
    window.isOpaque = false
    window.backgroundColor = .clear
    window.hasShadow = false
    window.isReleasedWhenClosed = false
    layout()
    window.orderFront(nil)
  }

  /** 屏幕变了（接显示器、改分辨率、程序坞挪位置）就重新铺 */
  func layout() {
    let s = screen
    window.setFrame(s.frame, display: true)
    window.contentView = NSHostingView(rootView: DeskRoot(model: model, insets: insetsOf(s), screenKey: screenKey(s)))
  }

  func close() {
    window.orderOut(nil)
    window.contentView = nil
  }
}

/** 无边框窗口默认当不了「键盘焦点窗口」，浮层要收键盘（Esc）就得自己开 */
final class OverlayPanel: NSPanel {
  var onEsc: (() -> Void)?
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { true }
  override func cancelOperation(_ sender: Any?) { onEsc?() }
}

@MainActor
final class Overlay: NSObject, NSWindowDelegate {
  private let model: DeskModel
  private var panel: OverlayPanel?
  private var dropTimer: Timer?
  private var batteryTimer: Timer?
  private var previousApp: NSRunningApplication?
  var openConsole: (Chat?) -> Void = { _ in }
  var onVisible: (Bool) -> Void = { _ in }
  static let keep: TimeInterval = 3 * 60

  init(model: DeskModel) { self.model = model }

  var isVisible: Bool { panel?.isVisible == true }

  func toggle() { isVisible ? hide(restore: true) : show() }

  func show(page: String? = nil) {
    dropTimer?.invalidate()
    if let page { model.page = page }
    let front = NSWorkspace.shared.frontmostApplication
    if front?.bundleIdentifier != Bundle.main.bundleIdentifier { previousApp = front }
    let p = panel ?? build()
    panel = p
    // 只铺主屏时浮层固定在主屏；每块屏都铺时，浮层开在鼠标所在的那块屏（编辑的就是那块屏的布局）
    let all = model.store.data["screens"] as? String == "all"
    let mouse = NSEvent.mouseLocation
    let s = all ? (NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? mainScreen()) : mainScreen()
    model.overlayKey = screenKey(s)
    p.setFrame(s.frame, display: false)
    p.contentView = host(insets: insetsOf(s))
    NSApp.activate(ignoringOtherApps: true)
    p.makeKeyAndOrderFront(nil)
    model.overlayVisible = true
    onVisible(true)
    // 电量只在浮层顶栏显示：浮层开着才读，一分钟一次
    Task { await model.refreshBattery() }
    batteryTimer?.invalidate()
    batteryTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
      Task { @MainActor in await self?.model.refreshBattery() }
    }
  }

  /** restore=true：Esc / 快捷键收起，把焦点还给呼出前的软件；失焦收起时不还（否则会切回那个软件所在的桌面空间） */
  func hide(restore: Bool) {
    guard let p = panel, p.isVisible else { return }
    model.editing = false
    model.overlayVisible = false
    model.mailOpen = nil
    model.symbolOpen = nil
    model.configOpen = nil
    onVisible(false)
    batteryTimer?.invalidate()
    p.orderOut(nil)
    if restore, let app = previousApp, !app.isTerminated { app.activate() }
    dropTimer?.invalidate()
    dropTimer = Timer.scheduledTimer(withTimeInterval: Overlay.keep, repeats: false) { [weak self] _ in
      Task { @MainActor in self?.drop() }
    }
  }

  /** 收起 3 分钟后整个销毁：界面树和磨砂层都不占内存，下次按快捷键再建（很快） */
  private func drop() {
    guard let p = panel, !p.isVisible else { return }
    p.contentView = nil
    p.close()
    panel = nil
    model.page = "home"
  }

  private func build() -> OverlayPanel {
    let p = OverlayPanel(contentRect: mainScreen().frame, styleMask: [.borderless, .fullSizeContentView], backing: .buffered, defer: true)
    p.level = .floating
    p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
    p.isOpaque = false
    p.backgroundColor = .clear
    p.hasShadow = false
    p.hidesOnDeactivate = false
    p.isReleasedWhenClosed = false
    p.isMovable = false
    p.delegate = self
    p.onEsc = { [weak self] in
      guard let self else { return }
      if self.model.editing { self.model.editing = false } else { self.hide(restore: true) }
    }
    return p
  }

  private func host(insets: Insets) -> NSView {
    let fx = NSVisualEffectView()
    fx.material = .hudWindow
    fx.blendingMode = .behindWindow
    fx.state = .active
    let h = NSHostingView(rootView: OverlayRoot(model: model, insets: insets, close: { [weak self] in self?.hide(restore: true) },
                                                openConsole: { [weak self] c in self?.hide(restore: false); self?.openConsole(c) }))
    h.translatesAutoresizingMaskIntoConstraints = false
    fx.addSubview(h)
    NSLayoutConstraint.activate([
      h.leadingAnchor.constraint(equalTo: fx.leadingAnchor), h.trailingAnchor.constraint(equalTo: fx.trailingAnchor),
      h.topAnchor.constraint(equalTo: fx.topAnchor), h.bottomAnchor.constraint(equalTo: fx.bottomAnchor),
    ])
    return fx
  }

  nonisolated func windowDidResignKey(_ notification: Notification) {
    MainActor.assumeIsolated { self.hide(restore: false) }
  }
}
