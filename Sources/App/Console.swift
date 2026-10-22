// AI 总控台（精简版，用户 2026-10-22 定）：智能体切换、会话列表、对话、接着上次的会话聊。
// 去掉了旧版的用量面板、worktree、diff 预览、置顶；OpenClaw 不再接；Muse 点一下用浏览器打开。
// Claude Code 的会话就是 ~/.claude/projects 里的那些（和你在终端里用的是同一批），DeepSeek 的对话只在这次运行里保留。
// 窗口按需创建、关掉就释放。
import SwiftUI
import AppKit

@MainActor
final class ConsoleModel: ObservableObject {
  @Published var agent = "claude"
  @Published var claudeList: [ClaudeSessionInfo] = []
  @Published var chats: [Chat] = []           // 这次运行里开过的对话（两家都有）
  @Published var current: Chat?
  @Published var loading = false
  var lastCwd = NSHomeDirectory()

  func reload() {
    loading = true
    Task.detached {
      let l = ClaudeSessions.list()
      await MainActor.run { self.claudeList = l; self.loading = false }
    }
  }

  func open(_ c: Chat) {
    if !chats.contains(where: { $0 === c }) { chats.insert(c, at: 0) }
    agent = c.agent
    current = c
  }

  func openClaude(_ s: ClaudeSessionInfo) {
    if let c = chats.first(where: { $0.claudeSession == s.id }) { current = c; return }
    let c = Chat(agent: "claude", cwd: s.cwd.isEmpty ? NSHomeDirectory() : s.cwd, claudeSession: s.id, items: [])
    c.title = s.title
    open(c)
    Task.detached {
      let h = ClaudeSessions.history(s.file)
      await MainActor.run { c.items = h }
    }
  }

  func newChat(_ agent: String) {
    if agent == "claude" {
      let p = NSOpenPanel()
      p.canChooseDirectories = true; p.canChooseFiles = false
      p.message = L("Claude Code 在哪个文件夹里工作？")
      p.directoryURL = URL(fileURLWithPath: lastCwd)
      guard p.runModal() == .OK, let u = p.url else { return }
      lastCwd = u.path
      open(Chat(agent: "claude", cwd: u.path))
    } else {
      open(Chat(agent: "deepseek"))
    }
  }
}

final class ConsoleWindow: NSObject, NSWindowDelegate {
  private var window: NSWindow?
  private var cm: ConsoleModel?
  private let model: DeskModel

  init(model: DeskModel) { self.model = model }

  @MainActor func show(chat: Chat? = nil, agent: String? = nil) {
    if window == nil {
      let cm = ConsoleModel()
      self.cm = cm
      let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1080, height: 720), styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
      w.title = L("AI 总控台")
      w.titlebarAppearsTransparent = true
      w.isReleasedWhenClosed = false
      w.minSize = NSSize(width: 760, height: 480)
      w.appearance = NSAppearance(named: .darkAqua)
      w.contentView = NSHostingView(rootView: ConsoleView(cm: cm, model: model).environment(\.pal, Palette.make(dark: true)))
      w.center()
      w.delegate = self
      window = w
      cm.reload()
    }
    if let chat { cm?.open(chat) }
    if let agent { cm?.agent = agent }
    NSApp.activate(ignoringOtherApps: true)
    window?.makeKeyAndOrderFront(nil)
  }

  /** 关掉就释放：界面树、对话记录都不再占内存（正在跑的 Claude 进程也停掉） */
  func windowWillClose(_ notification: Notification) {
    MainActor.assumeIsolated {
      for c in cm?.chats ?? [] where c !== model.overlayChat { c.cancel() }
      window?.contentView = nil
      window = nil
      cm = nil
    }
  }
}

struct ConsoleView: View {
  @Environment(\.pal) var pal
  @ObservedObject var cm: ConsoleModel
  @ObservedObject var model: DeskModel

  var body: some View {
    HStack(spacing: 0) {
      sidebar.frame(width: 260)
      Rectangle().fill(pal.line).frame(width: 0.5)
      if let c = cm.current { ChatPane(chat: c, model: model).id(c.id) } else { welcome }
    }
    .background(Color(r: 24, g: 26, b: 31))
    .foregroundStyle(pal.text)
  }

  private var sidebar: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 2) {
        ForEach([("claude", "Claude Code"), ("deepseek", "DeepSeek")], id: \.0) { id, n in
          Button { cm.agent = id } label: {
            Text(n).font(Font2.ui(12, .medium)).foregroundStyle(cm.agent == id ? pal.text : pal.text2).frame(maxWidth: .infinity)
              .padding(.vertical, 5).background(Capsule().fill(cm.agent == id ? pal.fill2 : .clear))
          }.buttonStyle(.plain)
        }
      }.padding(2).background(Capsule().fill(pal.fill))
      HStack {
        Button(L("＋ 新对话")) { cm.newChat(cm.agent) }.buttonStyle(PillButton())
        Spacer()
        Button("Muse ↗") { model.openURL("https://muse.ai/") }.buttonStyle(MiniButton()).help(L("在浏览器里打开 Muse"))
        if cm.agent == "claude" { Button { cm.reload() } label: { Image(systemName: "arrow.clockwise") }.buttonStyle(MiniButton()).help(L("重新读本机的 Claude 会话")) }
      }
      ScrollView {
        VStack(alignment: .leading, spacing: 2) {
          let mine = mineChats
          if !mine.isEmpty {
            Text(L("这次打开的")).font(Font2.ui(11)).foregroundStyle(pal.text3).padding(.top, 4)
            ForEach(mine) { c in sessionRow(title: c.title, sub: c.agent == "claude" ? folder(c.cwd) : (c.busy ? L("正在回复") : "DeepSeek"), on: cm.current === c) { cm.current = c } }
          }
          if cm.agent == "claude" {
            Text(cm.loading ? L("正在读取本机的会话…") : L("本机的 Claude 会话")).font(Font2.ui(11)).foregroundStyle(pal.text3).padding(.top, 8)
            ForEach(cm.claudeList) { s in
              sessionRow(title: s.title, sub: "\(folder(s.cwd)) · \(F.rel(s.updated))", on: cm.current?.claudeSession == s.id) { cm.openClaude(s) }
            }
          } else if mine.isEmpty {
            Text(L("DeepSeek 的对话只在这次运行里保留")).font(Font2.ui(11.5)).foregroundStyle(pal.text3).padding(.top, 8)
          }
        }
      }
    }
    .padding(14).padding(.top, 24)
  }

  /** 这次打开的对话里，不在「本机会话」列表里的那些（新开的、DeepSeek 的） */
  private var mineChats: [Chat] {
    let known = Set(cm.claudeList.map(\.id))
    return cm.chats.filter { c in
      guard c.agent == cm.agent else { return false }
      if c.agent == "deepseek" { return true }
      guard let s = c.claudeSession else { return true }
      return !known.contains(s)
    }
  }

  private func folder(_ p: String) -> String { p == NSHomeDirectory() ? "~" : (p as NSString).lastPathComponent }

  private func sessionRow(title: String, sub: String, on: Bool, _ action: @escaping () -> Void) -> some View {
    Button(action: action) {
      VStack(alignment: .leading, spacing: 2) {
        Text(title).font(Font2.ui(12.5, .medium)).foregroundStyle(pal.text).lineLimit(1)
        Text(sub).font(Font2.ui(11)).foregroundStyle(pal.text3).lineLimit(1)
      }.padding(.horizontal, 10).padding(.vertical, 7).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(on ? pal.fill2 : .clear)).contentShape(Rectangle())
    }.buttonStyle(.plain)
  }

  private var welcome: some View {
    VStack(spacing: 10) {
      Image(systemName: "sparkles").font(.system(size: 30)).foregroundStyle(pal.text3)
      Text(cm.agent == "claude" ? L("选一个左边的会话接着聊，或者新开一个（先选它在哪个文件夹里工作）") : L("新开一段和 DeepSeek 的对话")).font(Font2.ui(13)).foregroundStyle(pal.text2)
      Button(L("＋ 新对话")) { cm.newChat(cm.agent) }.buttonStyle(PillButton())
    }.frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

struct ChatPane: View {
  @Environment(\.pal) var pal
  @ObservedObject var chat: Chat
  @ObservedObject var model: DeskModel
  @State private var text = ""

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 10) {
        VStack(alignment: .leading, spacing: 2) {
          Text(chat.title).font(Font2.ui(14, .semibold)).lineLimit(1)
          Text(chat.agent == "claude" ? "Claude Code · \(chat.cwd)" : "DeepSeek · \(model.deepseekModel == "deepseek-reasoner" ? L("推理") : L("对话"))").font(Font2.ui(11)).foregroundStyle(pal.text3).lineLimit(1)
        }
        Spacer()
        if chat.agent == "claude" {
          Picker("", selection: $chat.permission) {
            Text(L("只读")).tag("default")
            Text(L("可以改文件")).tag("acceptEdits")
          }.pickerStyle(.segmented).frame(width: 180).labelsHidden()
            .help(L("只读：要改文件、跑命令会被拒绝。可以改文件：允许它直接改这个文件夹里的文件（命令仍然会被拒绝）"))
        }
        if chat.busy { Button(L("停止")) { chat.cancel() }.buttonStyle(PillButton()) }
      }
      .padding(.horizontal, 20).padding(.top, 30).padding(.bottom, 12)
      Rectangle().fill(pal.line).frame(height: 0.5)
      ScrollViewReader { sv in
        ScrollView {
          VStack(alignment: .leading, spacing: 14) {
            ForEach(chat.items) { ItemView(item: $0) }
            if chat.busy { ProgressView().controlSize(.small) }
            Color.clear.frame(height: 1).id("end")
          }.padding(20).frame(maxWidth: 820).frame(maxWidth: .infinity)
        }
        .onChange(of: chat.items.count) { _, _ in sv.scrollTo("end", anchor: .bottom) }
        .onChange(of: chat.items.last?.text) { _, _ in sv.scrollTo("end", anchor: .bottom) }
        .onAppear { sv.scrollTo("end", anchor: .bottom) }
      }
      HStack(spacing: 8) {
        TextField(chat.agent == "claude" ? L("给 Claude Code 发消息（回车发送，⌥回车换行）") : L("给 DeepSeek 发消息（回车发送）"), text: $text, axis: .vertical)
          .textFieldStyle(.plain).font(Font2.ui(13.5)).lineLimit(1...8).onSubmit(send)
        Button { chat.busy ? chat.cancel() : send() } label: {
          Image(systemName: chat.busy ? "stop.fill" : "arrow.up").font(.system(size: 12, weight: .bold)).foregroundStyle(.black.opacity(0.8))
            .frame(width: 30, height: 30).background(Circle().fill(.white.opacity(0.9)))
        }.buttonStyle(.plain)
      }
      .padding(.leading, 16).padding(.trailing, 7).padding(.vertical, 7)
      .background(RoundedRectangle(cornerRadius: 20).fill(pal.fill))
      .padding(16).frame(maxWidth: 852)
    }
  }

  private func send() {
    let t = text.trimmed()
    guard !t.isEmpty, !chat.busy else { return }
    text = ""
    chat.send(shown: t, prompt: t, model: model.deepseekModel)
  }
}
