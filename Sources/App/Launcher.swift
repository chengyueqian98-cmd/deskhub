// 应用 / 桌面启动器（浮层中间，从 AI 输入条左边的圆按钮或 ⌘E 展开）：
// 「应用」像启动台一样列出全部 App；「桌面」收着 ~/Desktop 里的文件，配合「隐藏桌面图标」让桌面保持干净。
// 单击选中，双击或回车打开，拖出可以放进别的软件，右键在访达中显示。
import SwiftUI
import AppKit

struct LaunchItem: Identifiable, Equatable {
  var id: String { path }
  let name: String
  let path: String
  var kind = "app"
  var cloud = false
  var mtime: Double = 0
  var size: Int?
}

@MainActor
final class LauncherModel: ObservableObject {
  @Published var tab: String = UserDefaults.standard.string(forKey: "launcher.tab") ?? "apps" { didSet { UserDefaults.standard.set(tab, forKey: "launcher.tab"); load() } }
  @Published var apps: [LaunchItem] = []
  @Published var files: [LaunchItem] = []
  @Published var query = ""
  @Published var filter = "all"
  @Published var sort: String = UserDefaults.standard.string(forKey: "launcher.sort") ?? "name" { didSet { UserDefaults.standard.set(sort, forKey: "launcher.sort") } }
  @Published var selected: String?
  @Published var iconsHidden = false
  private var icons: [String: NSImage] = [:]
  static let appDirs = ["/Applications", "/Applications/Utilities", "/System/Applications", "/System/Applications/Utilities", NSHomeDirectory() + "/Applications"]
  static var desktop: String { NSHomeDirectory() + "/Desktop" }

  func load(fresh: Bool = false) {
    if tab == "apps" {
      if apps.isEmpty || fresh { apps = LauncherModel.scanApps() }
    } else {
      files = LauncherModel.scanDesktop()
      iconsHidden = LauncherModel.readIconsHidden()
    }
  }

  /** 和启动台一样的范围；名字用系统的显示名（中文系统下是中文，比如「访达」） */
  static func scanApps() -> [LaunchItem] {
    var seen: [String: String] = [:]
    for dir in appDirs {
      for n in (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? [] where n.lowercased().hasSuffix(".app") && !n.hasPrefix(".") {
        if seen[n.lowercased()] == nil { seen[n.lowercased()] = dir + "/" + n }
      }
    }
    return seen.values.map { p in
      LaunchItem(name: FileManager.default.displayName(atPath: p).replacingOccurrences(of: ".app", with: ""), path: p)
    }
    .filter { !$0.name.test("^(Install macOS|Uninstall)", .caseInsensitive) }
    .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
  }

  static func scanDesktop() -> [LaunchItem] {
    let fm = FileManager.default
    return ((try? fm.contentsOfDirectory(atPath: desktop)) ?? []).compactMap { n in
      let p = desktop + "/" + n
      var dir: ObjCBool = false
      fm.fileExists(atPath: p, isDirectory: &dir)
      guard let it = DeskFiles.item(n, isDir: dir.boolValue) else { return nil }
      let attr = try? fm.attributesOfItem(atPath: p)
      return LaunchItem(name: it.name, path: p, kind: it.kind, cloud: it.cloud,
                        mtime: ((attr?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0) * 1000,
                        size: dir.boolValue ? nil : (attr?[.size] as? Int))
    }
  }

  var list: [LaunchItem] {
    let q = query.trimmed().lowercased()
    if tab == "apps" { return apps.filter { q.isEmpty || $0.name.lowercased().contains(q) || $0.path.lowercased().contains(q) } }
    return files
      .filter { filter == "all" || $0.kind == filter || (filter == "other" && !["folder", "doc", "image"].contains($0.kind)) }
      .filter { q.isEmpty || $0.name.lowercased().contains(q) }
      .sorted {
        if sort == "mtime" { return $0.mtime > $1.mtime }
        // 名称排序：文件夹在前（和访达一样）
        if ($0.kind == "folder") != ($1.kind == "folder") { return $0.kind == "folder" }
        return $0.name.localizedStandardCompare($1.name) == .orderedAscending
      }
  }

  func icon(_ p: String) -> NSImage {
    if let i = icons[p] { return i }
    let i = NSWorkspace.shared.icon(forFile: p)
    i.size = NSSize(width: 64, height: 64)
    icons[p] = i
    return i
  }

  func open(_ it: LaunchItem?) {
    guard let it else { return }
    let url = URL(fileURLWithPath: it.path)
    if tab == "apps" { NSWorkspace.shared.openApplication(at: url, configuration: .init()) } else { NSWorkspace.shared.open(url) }
  }

  func reveal(_ it: LaunchItem) { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: it.path)]) }

  // —— 隐藏 / 显示桌面图标（访达的 CreateDesktop 设置，改完要重启访达才生效；文件本身不动） ——
  static func readIconsHidden() -> Bool {
    let v = UserDefaults(suiteName: "com.apple.finder")?.object(forKey: "CreateDesktop")
    if let b = v as? Bool { return !b }
    if let s = v as? String { return s == "0" || s == "false" }
    return false
  }

  func setIconsHidden(_ hide: Bool) async {
    if hide { _ = await Fetch.run("/usr/bin/defaults", ["write", "com.apple.finder", "CreateDesktop", "-bool", "false"]) }
    else { _ = await Fetch.run("/usr/bin/defaults", ["delete", "com.apple.finder", "CreateDesktop"]) }
    _ = await Fetch.run("/usr/bin/killall", ["Finder"])
    iconsHidden = LauncherModel.readIconsHidden()
  }
}

struct LauncherPanel: View {
  @Environment(\.pal) var pal
  @ObservedObject var lm: LauncherModel
  @State private var askHide = false
  private let cols = [GridItem(.adaptive(minimum: 92, maximum: 110), spacing: 8)]

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 10) {
        Picker("", selection: $lm.tab) {
          Label(L("应用"), systemImage: "square.grid.2x2").tag("apps")
          Label(L("桌面"), systemImage: "folder").tag("desk")
        }.pickerStyle(.segmented).frame(width: 170).labelsHidden()
        TextField(lm.tab == "apps" ? "搜索 \(lm.apps.count) 个应用" : "搜索桌面上的文件", text: $lm.query)
          .textFieldStyle(.plain).font(Font2.ui(13)).padding(.horizontal, 12).padding(.vertical, 6)
          .background(Capsule().fill(pal.fill)).frame(width: 240)
          .onSubmit { lm.open(lm.list.first) }
        Spacer()
        if lm.tab == "apps" {
          Button(L("刷新")) { lm.load(fresh: true) }.buttonStyle(MiniButton()).help(L("装了新 App 后点一下"))
        } else {
          Toggle(L("隐藏桌面图标"), isOn: Binding(get: { lm.iconsHidden }, set: { _ in askHide = true })).toggleStyle(.switch).controlSize(.mini).font(Font2.ui(11.5))
          Button(L("在访达中打开")) { NSWorkspace.shared.open(URL(fileURLWithPath: LauncherModel.desktop)) }.buttonStyle(MiniButton())
        }
      }
      if lm.tab == "desk" {
        HStack(spacing: 6) {
          ForEach([("all", "全部"), ("folder", "文件夹"), ("doc", "文档"), ("image", "图片"), ("other", "其他")], id: \.0) { k, n in
            Button(n) { lm.filter = k }.buttonStyle(ChipStyle(on: lm.filter == k))
          }
          Spacer()
          Picker("", selection: $lm.sort) { Text(L("名称")).tag("name"); Text(L("最近修改")).tag("mtime") }.pickerStyle(.segmented).frame(width: 150).labelsHidden()
        }
      }
      MaybeScroll {
        let items = lm.list
        if items.isEmpty {
          Text(lm.query.isEmpty ? (lm.tab == "apps" ? "加载中…" : "桌面上没有东西") : "没有找到").font(Font2.ui(12.5)).foregroundStyle(pal.text3).padding(30)
        }
        LazyVGrid(columns: cols, spacing: 10) {
          ForEach(items) { it in cell(it) }
        }
      }
    }
    .padding(16)
    .frame(width: 760, height: 430)
    .background(RoundedRectangle(cornerRadius: 20).fill(.black.opacity(0.45)))
    .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(pal.line, lineWidth: 0.5))
    .onAppear { lm.load() }
    .alert(lm.iconsHidden ? "显示桌面图标？" : "隐藏桌面图标？", isPresented: $askHide) {
      Button(lm.iconsHidden ? "显示" : "隐藏") { Task { await lm.setIconsHidden(!lm.iconsHidden) } }
      Button(L("取消"), role: .cancel) {}
    } message: {
      Text(L("文件不会动，还在桌面文件夹里。需要重启一下访达才生效（会关掉已打开的访达窗口）。"))
    }
  }

  private func cell(_ it: LaunchItem) -> some View {
    VStack(spacing: 5) {
      ZStack(alignment: .bottomTrailing) {
        Image(nsImage: lm.icon(it.path)).resizable().frame(width: 52, height: 52)
        if it.cloud { Image(systemName: "icloud").font(.system(size: 10)).foregroundStyle(pal.text2) }
      }
      Text(it.name).font(Font2.ui(11.5)).foregroundStyle(pal.text).lineLimit(2).multilineTextAlignment(.center).frame(height: 30, alignment: .top)
    }
    .padding(6)
    .frame(maxWidth: .infinity)
    .background(RoundedRectangle(cornerRadius: 10).fill(lm.selected == it.path ? pal.fill2 : .clear))
    .contentShape(Rectangle())
    .onTapGesture(count: 2) { lm.open(it) }
    .onTapGesture { lm.selected = it.path }
    .contextMenu {
      Button(L("打开")) { lm.open(it) }
      Button(L("在访达中显示")) { lm.reveal(it) }
    }
    .onDrag { NSItemProvider(object: URL(fileURLWithPath: it.path) as NSURL) }
    .help(it.name + (it.cloud ? "\n在 iCloud 里，打开时会下载" : "") + "\n双击打开 · 右键在访达中显示")
  }
}

struct ChipStyle: ButtonStyle {
  @Environment(\.pal) var pal
  let on: Bool
  func makeBody(configuration: Configuration) -> some View {
    configuration.label.font(Font2.ui(11.5, .medium)).foregroundStyle(on ? pal.text : pal.text3)
      .padding(.horizontal, 10).padding(.vertical, 4)
      .background(Capsule().fill(on ? pal.fill2 : .clear)).overlay(Capsule().strokeBorder(pal.line, lineWidth: on ? 0 : 0.5))
  }
}
