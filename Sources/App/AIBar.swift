// 浮层底部那条 AI 输入（管家就是 AI）：默认把行情、量化、计划、日程、邮件全带上；回答在上面展开，
// 想让它办事（加自选、记计划价、建提醒…）就会出一张确认卡，点「执行」才做。左边那个圆按钮是应用 / 桌面启动器。
import SwiftUI

struct AIBar: View {
  @Environment(\.pal) var pal
  @ObservedObject var model: DeskModel
  @ObservedObject var chat: Chat
  @Binding var launcherOpen: Bool
  let openConsole: (Chat) -> Void
  @State private var text = ""
  @State private var ctx: Set<String> = Set(DeskModel.ctxKinds.map(\.0))
  @FocusState private var focused: Bool

  var body: some View {
    VStack(spacing: 8) {
      if !chat.items.isEmpty { thread }
      if focused || !chat.items.isEmpty { options }
      HStack(spacing: 10) {
        Button { launcherOpen.toggle() } label: {
          Image(systemName: launcherOpen ? "chevron.down" : "square.grid.2x2").font(.system(size: 15, weight: .medium)).foregroundStyle(pal.text)
            .frame(width: 44, height: 44).background(Circle().fill(.black.opacity(0.35))).overlay(Circle().strokeBorder(pal.line, lineWidth: 0.5))
        }.buttonStyle(.plain).help(L("应用和桌面（⌘E）"))
        HStack(spacing: 8) {
          TextField(L("问%@…（回车发送）", model.store.butlerName), text: $text, axis: .vertical)
            .textFieldStyle(.plain).font(Font2.ui(14)).foregroundStyle(pal.text).lineLimit(1...6)
            .focused($focused).onSubmit(send)
          Button { chat.busy ? chat.cancel() : send() } label: {
            Image(systemName: chat.busy ? "stop.fill" : "arrow.up").font(.system(size: 12, weight: .bold)).foregroundStyle(.black.opacity(0.8))
              .frame(width: 30, height: 30).background(Circle().fill(.white.opacity(text.isEmpty && !chat.busy ? 0.35 : 0.9)))
          }.buttonStyle(.plain)
        }
        .padding(.leading, 18).padding(.trailing, 7).padding(.vertical, 7)
        .background(Capsule().fill(.black.opacity(0.35)))
        .overlay(Capsule().strokeBorder(focused ? pal.accent : pal.line, lineWidth: focused ? 1.2 : 0.5))
      }
    }
    .frame(width: 680)
    .onReceive(NotificationCenter.default.publisher(for: .focusAI)) { _ in focused = true }
  }

  private func send() {
    let t = text.trimmed()
    guard !t.isEmpty, !chat.busy else { return }
    text = ""
    let b = model.buildPrompt(t, ctx: ctx)
    chat.send(shown: t, prompt: b.prompt, model: model.deepseekModel, parseActions: b.allowActions, withMail: ctx.contains("mail"))
  }

  // —— 用谁 / 附上什么（一行放下，不换行） ——
  private var options: some View {
    HStack(spacing: 6) {
      ForEach([("deepseek", "DeepSeek"), ("claude", "Claude Code")], id: \.0) { id, name in
        chip(name, on: model.aiAgent == id) {
          guard !chat.busy, model.aiAgent != id else { return }
          model.store.set(["aiAgent": id])
          model.newOverlayChat()
        }
      }
      Rectangle().fill(pal.line).frame(width: 0.5, height: 14).padding(.horizontal, 4)
      Text(L("附上")).font(Font2.ui(11.5)).foregroundStyle(pal.text3)
      ForEach(DeskModel.ctxKinds, id: \.0) { k, _ in
        chip(L(DeskModel.ctxShort[k] ?? k), on: ctx.contains(k)) { if ctx.contains(k) { ctx.remove(k) } else { ctx.insert(k) } }
      }
    }
    .fixedSize()
  }

  private func chip(_ t: String, on: Bool, _ action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Text(t).font(Font2.ui(11.5, .medium)).foregroundStyle(on ? pal.text : pal.text3)
        .padding(.horizontal, 10).padding(.vertical, 4)
        .background(Capsule().fill(on ? pal.fill2 : .clear)).overlay(Capsule().strokeBorder(pal.line, lineWidth: on ? 0 : 0.5))
    }.buttonStyle(.plain)
  }

  // —— 对话 ——
  private var thread: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 8) {
        Image(systemName: "sparkle").font(.system(size: 11)).foregroundStyle(pal.accent)
        Text("\(model.store.butlerName) · \(chat.agentName)" + (chat.busy ? L(" · 正在回复") : "")).font(Font2.ui(12, .medium)).foregroundStyle(pal.text2)
        Spacer()
        Button(L("在总控台中继续")) { openConsole(chat) }.buttonStyle(MiniButton())
        Button(L("新对话")) { model.newOverlayChat() }.buttonStyle(MiniButton())
      }
      .padding(.horizontal, 16).padding(.vertical, 10)
      Rectangle().fill(pal.line).frame(height: 0.5)
      ScrollViewReader { sv in
        MaybeScroll {
          VStack(alignment: .leading, spacing: 12) {
            ForEach(chat.items) { it in ItemView(item: it).id(it.id) }
            if chat.busy { ProgressView().controlSize(.small).padding(.leading, 2) }
            if let p = chat.pending { ActionCard(model: model, chat: chat, pending: p) }
            Color.clear.frame(height: 1).id("end")
          }
          .padding(16)
        }
        .frame(maxHeight: 420)
        .onChange(of: chat.items.last?.text) { _, _ in sv.scrollTo("end", anchor: .bottom) }
        .onChange(of: chat.items.count) { _, _ in sv.scrollTo("end", anchor: .bottom) }
        .onChange(of: chat.pending?.list.count) { _, _ in sv.scrollTo("end", anchor: .bottom) }
      }
    }
    .background(RoundedRectangle(cornerRadius: 18).fill(.black.opacity(0.42)))
    .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(pal.line, lineWidth: 0.5))
  }
}

extension Notification.Name { static let focusAI = Notification.Name("deskhub.focusAI") }

struct MiniButton: ButtonStyle {
  @Environment(\.pal) var pal
  func makeBody(configuration: Configuration) -> some View {
    configuration.label.font(Font2.ui(11.5)).foregroundStyle(pal.text2)
      .padding(.horizontal, 9).padding(.vertical, 3)
      .background(Capsule().fill(configuration.isPressed ? pal.fill2 : pal.fill))
  }
}

/** 一条对话：用户的话靠右，回答是正文（支持加粗、代码、链接这些行内格式），工具调用是一行小字 */
struct ItemView: View {
  @Environment(\.pal) var pal
  let item: TItem
  var body: some View {
    switch item.kind {
    case .user:
      HStack {
        Spacer(minLength: 60)
        Text(item.text).font(Font2.ui(13.5)).foregroundStyle(pal.text).textSelection(.enabled)
          .padding(.horizontal, 12).padding(.vertical, 8).background(RoundedRectangle(cornerRadius: 12).fill(pal.fill2))
      }
    case .ai:
      Text(markdown(Chat.display(item))).font(Font2.ui(13.5)).foregroundStyle(pal.text).lineSpacing(3).textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    case .tool:
      HStack(alignment: .firstTextBaseline, spacing: 6) {
        Image(systemName: item.failed ? "exclamationmark.circle" : "gearshape").font(.system(size: 10))
        Text(L(item.text)).font(Font2.ui(11.5, .medium))
        Text(item.detail).font(.system(size: 11, design: .monospaced)).lineLimit(2)
      }.foregroundStyle(item.failed ? pal.orange : pal.text3)
    case .notice:
      Text(item.text).font(Font2.ui(11.5)).foregroundStyle(pal.text3)
    case .error:
      Text(item.text).font(Font2.ui(12.5)).foregroundStyle(pal.orange).textSelection(.enabled)
    }
  }

  private func markdown(_ s: String) -> AttributedString {
    (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(s)
  }
}

/** 确认卡：每一行都是根据校验后的参数生成的（模型写的说明文字不上卡）；点了「执行」才做 */
struct ActionCard: View {
  @Environment(\.pal) var pal
  @ObservedObject var model: DeskModel
  @ObservedObject var chat: Chat
  let pending: PendingActions

  var body: some View {
    let any = pending.list.contains(where: \.ok)
    VStack(alignment: .leading, spacing: 8) {
      Text(pending.results != nil ? L("执行结果") : model.store.butlerName + (any ? L("想做这些事（点「执行」才会做）") : L("想做的事，但都做不了")))
        .font(Font2.ui(12.5, .semibold)).foregroundStyle(pal.text)
      if let res = pending.results {
        ForEach(Array(res.enumerated()), id: \.offset) { _, r in
          Text("\(r.ok ? "✓" : "✗") \(r.text)").font(Font2.ui(12.5)).foregroundStyle(r.ok ? pal.text2 : pal.orange)
        }
      } else {
        ForEach(Array(pending.list.enumerated()), id: \.offset) { _, x in
          if let a = x.action { Text("· " + Actions.describe(a)).font(Font2.ui(12.5)).foregroundStyle(pal.text2) }
          else { Text(L("✗ 不执行：") + (x.error ?? "")).font(Font2.ui(12.5)).foregroundStyle(pal.orange) }
        }
        if pending.withMail { Text(L("这一问附带了邮件内容。邮件是别人写的，请确认这些操作确实是你自己要的。")).font(Font2.ui(11.5)).foregroundStyle(pal.orange) }
      }
      HStack(spacing: 8) {
        if pending.results == nil && any {
          Button {
            guard !pending.running else { return }
            chat.pending?.running = true
            let todo = pending.list.compactMap(\.action)
            Task {
              let r = await model.runActions(todo, chat: chat)
              chat.pending?.results = r
              chat.items.append(TItem(kind: .notice, text: L("已执行 %@ / %@ 件", "\(r.filter(\.ok).count)", "\(r.count)")))
            }
          } label: {
            Text(L("执行")).font(Font2.ui(12, .semibold)).foregroundStyle(.white).padding(.horizontal, 14).padding(.vertical, 5).background(Capsule().fill(pal.accent))
          }.buttonStyle(.plain).disabled(pending.running)
          Button(L("取消")) { chat.pending = nil; chat.items.append(TItem(kind: .notice, text: L("已取消，什么都没做"))) }.buttonStyle(PillButton())
        } else {
          Button(L("知道了")) { chat.pending = nil }.buttonStyle(MiniButton())
        }
      }
    }
    .padding(14)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(RoundedRectangle(cornerRadius: 12).fill(pal.fill))
    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(pal.accent.opacity(0.4), lineWidth: 0.5))
  }
}

/** 邮件正文面板：点开某一封才读正文；可以让管家概括（正文会发给你选的 AI），或在「邮件」里打开 */
struct MailPanel: View {
  @Environment(\.pal) var pal
  @ObservedObject var model: DeskModel
  let id: String
  @State private var state: Fetch.MailBody?

  var body: some View {
    let meta = model.mail?.items.first { $0.id == id }
    SidePanel(close: { model.mailOpen = nil }) {
      VStack(alignment: .leading, spacing: 10) {
        Text(subject(meta)).font(Font2.ui(18, .semibold)).foregroundStyle(pal.text).textSelection(.enabled)
        Text("\(meta?.name ?? "")\(meta.map { $0.email.isEmpty ? "" : " <\($0.email)>" } ?? "")\(meta?.ts.map { " · " + F.rel($0) } ?? "")")
          .font(Font2.ui(12)).foregroundStyle(pal.text3)
        HStack(spacing: 8) {
          Button {
            guard case .ok(let n, let e, let s, let b) = state else { return }
            model.mailOpen = nil
            model.overlayChat.send(shown: L("概括邮件：") + s, prompt: DeskModel.askOne + (appLang == "en" ? " Please answer in English." : "") + "\n\n" + DeskModel.mailPrompt(n, e, s, b), model: model.deepseekModel)
          } label: {
            Text(L("让%@概括", model.store.butlerName)).font(Font2.ui(12, .semibold)).foregroundStyle(.white).padding(.horizontal, 14).padding(.vertical, 5).background(Capsule().fill(pal.accent))
          }.buttonStyle(.plain).disabled(!isOk)
          Button(L("在「邮件」中打开")) { model.openURL(MailAPI.messageUrl(id)) }.buttonStyle(PillButton())
        }
        Rectangle().fill(pal.line).frame(height: 0.5)
        switch state {
        case nil: Text(L("正在读取正文…")).font(Font2.ui(12.5)).foregroundStyle(pal.text3)
        case .failed(let e): Text(e).font(Font2.ui(12.5)).foregroundStyle(pal.orange)
        case .ok(_, _, _, let body):
          Text(body.isEmpty ? L("（没有正文）") : body).font(Font2.ui(13)).foregroundStyle(pal.text2).lineSpacing(3).textSelection(.enabled)
        }
      }
    }
    .task(id: id) { state = nil; state = await Fetch.mailBody(id) }
  }

  private var isOk: Bool { if case .ok = state { return true }; return false }
  private func subject(_ m: MailItem?) -> String {
    if case .ok(_, _, let s, _) = state { return s }
    return m?.subject ?? L("（无主题）")
  }
}

/** 右侧滑出的面板（邮件正文、品种详情），点外面或 Esc 关闭 */
struct SidePanel<Content: View>: View {
  @Environment(\.pal) var pal
  let close: () -> Void
  @ViewBuilder var content: () -> Content
  var body: some View {
    ZStack(alignment: .trailing) {
      Color.black.opacity(0.25).contentShape(Rectangle()).onTapGesture(perform: close)
      VStack(alignment: .leading, spacing: 0) {
        HStack {
          Spacer()
          Button(action: close) {
            Image(systemName: "xmark").font(.system(size: 11, weight: .semibold)).foregroundStyle(pal.text2).frame(width: 26, height: 26).background(Circle().fill(pal.fill))
          }.buttonStyle(.plain).keyboardShortcut(.cancelAction)
        }
        MaybeScroll { content().frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 24) }
      }
      .padding(20)
      .frame(width: 500)
      .frame(maxHeight: .infinity)
      .background(Color(r: 28, g: 30, b: 36, a: 0.97))
      .overlay(alignment: .leading) { Rectangle().fill(pal.line).frame(width: 0.5) }
    }
  }
}
