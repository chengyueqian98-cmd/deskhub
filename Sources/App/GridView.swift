// 网格：按 Layout 把小组件贴到格子上。桌面层只显示；浮层里可以编辑——
// 长按任意组件 0.6 秒（和 iOS 一样）或点顶栏「编辑」进编排：拖动换位置（显示松手会落在哪一格），
// 底部一排档位点一下换大小，左上角「−」收起，屏幕底部的编排条可以加回收起的组件、恢复默认。
import SwiftUI

struct GridView: View {
  @Environment(\.pal) var pal
  @ObservedObject var model: DeskModel
  let interactive: Bool
  var screenKey = "main"

  @State private var dragId: String?
  @State private var drag: CGSize = .zero

  var body: some View {
    GeometryReader { geo in
      let W = geo.size.width, H = geo.size.height
      let m = metrics(W, H)
      let gridW = Double(Grid.cols) * m.cellW + Double(Grid.cols + 1) * m.gap
      let ox = max(0, (W - gridW) / 2)   // 大屏上格子宽度到顶了，整块居中
      let items = model.layoutFor(screenKey).items.filter(\.on)
      let editing = interactive && model.editing
      ZStack(alignment: .topLeading) {
        if editing, let id = dragId, let it = items.first(where: { $0.id == id }) {
          let p = target(it, W, H)
          let r = toRect(col: p.col, row: p.row, w: it.w, h: it.h, W, H)
          RoundedRectangle(cornerRadius: 16).fill(pal.accent.opacity(0.14))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(pal.accent.opacity(0.6), lineWidth: 1))
            .frame(width: r.width, height: r.height).offset(x: ox + r.left, y: r.top)
        }
        ForEach(items, id: \.id) { it in
          let r = toRect(col: it.col, row: it.row, w: it.w, h: it.h, W, H)
          let isDrag = dragId == it.id
          cellView(it, size: CGSize(width: r.width, height: r.height), editing: editing)
            .frame(width: r.width, height: r.height, alignment: .topLeading)
            .offset(x: ox + r.left + (isDrag ? drag.width : 0), y: r.top + (isDrag ? drag.height : 0))
            .zIndex(isDrag ? 10 : 0)
            .gesture(editing ? dragGesture(it, W, H) : nil)
            .onLongPressGesture(minimumDuration: 0.6) { if interactive && !model.editing { model.editing = true } }
        }
      }
      .animation(dragId == nil ? .easeInOut(duration: 0.34) : nil, value: model.layoutFor(screenKey))
    }
  }

  private func target(_ it: LayoutItem, _ W: Double, _ H: Double) -> (col: Int, row: Int) {
    let r = toRect(col: it.col, row: it.row, w: it.w, h: it.h, W, H)
    let p = fromPoint(r.left + drag.width, r.top + drag.height, W, H)
    return (min(p.col, Grid.cols - it.w), min(p.row, max(0, Grid.rows - it.h)))
  }

  private func dragGesture(_ it: LayoutItem, _ W: Double, _ H: Double) -> some Gesture {
    DragGesture(minimumDistance: 4)
      .onChanged { v in dragId = it.id; drag = v.translation }
      .onEnded { _ in
        let p = target(it, W, H)
        dragId = nil
        drag = .zero
        if p.col != it.col || p.row != it.row { model.moveWidget(it.id, p.col, p.row) }
      }
  }

  @ViewBuilder private func cellView(_ it: LayoutItem, size: CGSize, editing: Bool) -> some View {
    let cell = Cell(id: it.id, size: size, sizeKey: it.size, interactive: interactive && !editing)
    let cards = model.theme.cards
    ZStack(alignment: .topLeading) {
      widget(cell, type: it.type)
        .padding(.top, 10)
        .padding(.horizontal, cards ? 14 : 0).padding(.bottom, cards ? 10 : 0)
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .background { if cards { RoundedRectangle(cornerRadius: 18).fill(pal.fill) } }
        .clipped()
        // 线条风格：每块顶上一条发丝线（每列最上面那块不画）；卡片风格：淡淡的底
        .overlay(alignment: .top) { if it.row > 0 && !cards { Rectangle().fill(pal.line).frame(height: 0.5) } }
        .opacity(editing ? 0.85 : 1)
        .allowsHitTesting(!editing)
      if editing { editChrome(it, size: size) }
    }
  }

  @ViewBuilder private func widget(_ c: Cell, type: String) -> some View {
    switch type {
    case "clock": ClockWidget(cell: c)
    case "butler": ButlerWidget(model: model, cell: c)
    case "weather": WeatherWidget(model: model, cell: c)
    case "market": MarketWidget(model: model, cell: c)
    case "calendar": CalendarWidget(model: model, cell: c)
    case "mail": MailWidget(model: model, cell: c)
    case "news": NewsWidget(model: model, cell: c)
    case "worldclock": WorldClockWidget(model: model, cell: c)
    case "risk": RiskWidget(model: model, cell: c)
    case "todo": TodoWidget(model: model, cell: c)
    case "countdown": CountdownWidget(model: model, cell: c)
    case "crypto": CryptoWidget(model: model, cell: c)
    case "github": GitHubWidget(model: model, cell: c)
    case "rss": FeedWidget(model: model, cell: c)
    case "photo": PhotoWidget(model: model, cell: c)
    case "pomodoro": PomodoroWidget(model: model, cell: c)
    case "sysstat": SysWidget(model: model, cell: c)
    case "note": NoteWidget(model: model, cell: c)
    case "fx": FXWidget(model: model, cell: c)
    case "lunar": LunarWidget(model: model, cell: c)
    case "nowplaying": NowPlayingWidget(model: model, cell: c)
    default: EmptyView()
    }
  }

  /** 编排态：没有底色就看不见也拖不动，所以临时给一个淡底 + 虚线框 */
  private func editChrome(_ it: LayoutItem, size: CGSize) -> some View {
    ZStack(alignment: .topLeading) {
      RoundedRectangle(cornerRadius: 16).fill(pal.fill)
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(pal.text3, style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
        .contentShape(Rectangle())
      Button { model.removeWidget(it.id) } label: {
        Image(systemName: "minus").font(.system(size: 11, weight: .bold)).foregroundStyle(.black.opacity(0.75))
          .frame(width: 20, height: 20).background(Circle().fill(.white.opacity(0.9)))
      }.buttonStyle(.plain).offset(x: -6, y: -6).help(L("收起这个组件"))
      if WidgetConfig.configurable.contains(it.type) {
        Button { model.configOpen = it.id } label: {
          Image(systemName: "gearshape.fill").font(.system(size: 11)).foregroundStyle(.black.opacity(0.75))
            .frame(width: 22, height: 22).background(Circle().fill(.white.opacity(0.9)))
        }.buttonStyle(.plain).frame(maxWidth: .infinity, alignment: .trailing).offset(x: 6, y: -6).help(L("这个组件的设置"))
      }
      if let def = widgetDef(it.type), def.sizes.count > 1 {
        HStack(spacing: 4) {
          ForEach(def.sizes, id: \.self) { s in
            Button { model.resizeWidget(it.id, s) } label: {
              Text(L(SIZES[s]!.label)).font(Font2.ui(11.5, .medium)).foregroundStyle(s == it.size ? .black : pal.text)
                .padding(.horizontal, 9).padding(.vertical, 3)
                .background(Capsule().fill(s == it.size ? .white.opacity(0.9) : pal.fill2))
            }.buttonStyle(.plain)
          }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom).padding(.bottom, 10)
      }
    }
    .frame(width: size.width, height: size.height)
  }
}
