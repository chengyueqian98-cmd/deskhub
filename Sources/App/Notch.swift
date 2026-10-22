// 刘海条：和物理刘海连成一块黑色，左边 CPU、右边内存；Apple Music 放歌时下面多一行歌词。点击穿透、不挡菜单栏。
//
// 比 Electron 版省的地方：
//   · CPU / 内存直接读系统统计（以前每 2 秒起一次 vm_stat）
//   · 「音乐」换歌、暂停会广播通知，平时不轮询；只在换歌 / 继续播放时用一次 AppleScript 对准进度，之后自己往前算
//   · 刘海位置用系统接口（auxiliaryTopLeftArea / RightArea），以前要起一个 osascript
import AppKit
import SwiftUI

@MainActor
final class NotchModel: ObservableObject {
  @Published var cpu: Int?
  @Published var mem: Int?
  @Published var line = ""                 // 当前这句歌词（或 ♪ 歌名）
  @Published var playing = false
  @Published var hasMusic = false
  var showLyrics = true

  private var lastCPU: (busy: UInt64, total: UInt64)?
  private var track = ""                   // 歌名|歌手
  private var lines: [LrcLine] = []
  private var position = 0.0, at = Date()  // 进度（秒）和那一刻的时间
  private var meta = ""
  private var lyricCache: [String: (lines: [LrcLine], at: Date)] = [:]

  // —— CPU：host_processor_info 两次采样的差 ——
  func sampleCPU() {
    var count: mach_msg_type_number_t = 0
    var info: processor_info_array_t?
    var n: natural_t = 0
    guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &n, &info, &count) == KERN_SUCCESS, let info else { return }
    var busy: UInt64 = 0, total: UInt64 = 0
    for i in 0..<Int(n) {
      let b = Int(CPU_STATE_MAX) * i
      let user = UInt64(info[b + Int(CPU_STATE_USER)]), sys = UInt64(info[b + Int(CPU_STATE_SYSTEM)])
      let nice = UInt64(info[b + Int(CPU_STATE_NICE)]), idle = UInt64(info[b + Int(CPU_STATE_IDLE)])
      busy += user + sys + nice
      total += user + sys + nice + idle
    }
    vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), vm_size_t(Int(count) * MemoryLayout<integer_t>.stride))
    if let l = lastCPU, total > l.total { cpu = Int((Double(busy - l.busy) / Double(total - l.total) * 100).rounded()) }
    lastCPU = (busy, total)
  }

  // —— 内存：活跃 + 联动 + 被压缩占用（接近「活动监视器」） ——
  func sampleMem() {
    var stats = vm_statistics64()
    var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
    let r = withUnsafeMutablePointer(to: &stats) { $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count) } }
    guard r == KERN_SUCCESS else { return }
    var page: vm_size_t = 0
    host_page_size(mach_host_self(), &page)
    let used = Double(UInt64(stats.active_count) + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)) * Double(page)
    mem = min(100, Int((used / Double(ProcessInfo.processInfo.physicalMemory) * 100).rounded()))
  }

  // —— 音乐 ——
  /** 「音乐」广播的播放信息（换歌、暂停、继续都会发） */
  func musicChanged(_ info: [AnyHashable: Any]) {
    let state = info["Player State"] as? String ?? ""
    if state == "Stopped" || state.isEmpty { hasMusic = false; playing = false; line = ""; return }
    hasMusic = true
    playing = state == "Playing"
    Task { await syncPosition() }
  }

  /** 用 AppleScript 对准一次进度；换歌了就去查歌词 */
  func syncPosition() async {
    guard showLyrics, NSWorkspace.shared.runningApplications.contains(where: { $0.bundleIdentifier == "com.apple.Music" }) else { hasMusic = false; return }
    let r = await Fetch.run("/usr/bin/osascript", ["-e", Lyrics.script], timeout: 5)
    guard let np = Lyrics.parseNowPlaying(r.out) else { hasMusic = false; line = ""; return }
    hasMusic = true
    playing = np.playing
    position = np.position
    at = Date()
    meta = "♪ \(np.title)\(np.artist.isEmpty ? "" : " — " + np.artist)"
    let key = "\(np.title)|\(np.artist)"
    if key != track {
      track = key
      lines = []
      lines = await fetchLyrics(title: np.title, artist: np.artist, duration: np.duration)
    }
    tick()
  }

  /** 每半秒算一次该显示哪一句；没变就不动界面 */
  func tick() {
    guard hasMusic, showLyrics else { if !line.isEmpty { line = "" }; return }
    let pos = position + (playing ? Date().timeIntervalSince(at) : 0) + 0.3   // 稍微提前一点，看着更跟拍
    let i = Lyrics.lineAt(lines, pos)
    let next = i >= 0 && !lines[i].text.isEmpty ? lines[i].text : meta
    if next != line { line = next }
  }

  /** LRCLIB 查歌词：中文歌常按繁体存，简体查不到就转繁体再查；查到的转回简体 */
  private func fetchLyrics(title: String, artist: String, duration: Double) async -> [LrcLine] {
    let key = "\(title)|\(artist)"
    if let c = lyricCache[key], !c.lines.isEmpty || Date().timeIntervalSince(c.at) < 600 { return c.lines }
    func api(_ path: String, _ q: [URLQueryItem]) async -> Any? {
      var c = URLComponents(string: "https://lrclib.net/api/" + path)!
      c.queryItems = q
      guard let d = try? await Fetch.get(c.url!, headers: ["User-Agent": "DeskHub/0.3 (personal desktop app)"], timeout: 8) else { return nil }
      return try? JSONSerialization.jsonObject(with: d)
    }
    let tt = title.applyingTransform(StringTransform("Hans-Hant"), reverse: false) ?? title
    let ta = artist.applyingTransform(StringTransform("Hans-Hant"), reverse: false) ?? artist
    var hit: JSON?
    for (t, a) in [(title, artist), (tt, ta)] {
      let got = await api("get", [.init(name: "track_name", value: t), .init(name: "artist_name", value: a), .init(name: "duration", value: String(Int(duration)))]) as? JSON
      hit = Lyrics.pickBest(got.map { [$0] } ?? [], duration: duration)
      if hit == nil { hit = Lyrics.pickBest(await api("search", [.init(name: "track_name", value: t), .init(name: "artist_name", value: a)]) as? [JSON] ?? [], duration: duration) }
      if hit != nil { break }
    }
    if hit == nil { hit = Lyrics.pickBest(await api("search", [.init(name: "q", value: "\(title) \(artist)")]) as? [JSON] ?? [], duration: duration) }
    let l = Lyrics.parse(hit?["syncedLyrics"] as? String).map { LrcLine(t: $0.t, text: News.t2s($0.text)) }
    lyricCache[key] = (l, Date())
    return l
  }
}

@MainActor
final class NotchWindow {
  private var window: NSWindow?
  private let nm = NotchModel()
  private var timers: [Timer] = []
  private var observer: NSObjectProtocol?
  static let wing: CGFloat = 150, lyricH: CGFloat = 30

  /** 有刘海的屏幕才显示（系统接口给出刘海左右两块菜单栏区域，中间就是刘海） */
  func setEnabled(_ on: Bool, lyrics: Bool) {
    nm.showLyrics = lyrics
    if !on { stop(); return }
    guard window == nil else { nm.tick(); return }
    guard let s = NSScreen.screens.first, let l = s.auxiliaryTopLeftArea, let r = s.auxiliaryTopRightArea, r.minX > l.maxX else { return }
    let notchW = r.minX - l.maxX, barH = s.safeAreaInsets.top
    let w = notchW + 2 * NotchWindow.wing, h = barH + NotchWindow.lyricH + 4
    let frame = NSRect(x: s.frame.minX + l.maxX - NotchWindow.wing, y: s.frame.maxY - h, width: w, height: h)
    let win = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    win.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 2)   // 在菜单栏上面
    win.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
    win.ignoresMouseEvents = true
    win.isOpaque = false
    win.backgroundColor = .clear
    win.hasShadow = false
    win.contentView = NSHostingView(rootView: NotchView(nm: nm, notchW: notchW, barH: barH))
    win.orderFrontRegardless()
    window = win
    nm.sampleCPU(); nm.sampleMem()
    timers = [
      Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.nm.sampleCPU(); self?.nm.sampleMem() } },
      Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.nm.tick() } },
      // 兜底：每 20 秒对一次进度（拖了进度条不会发通知）
      Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in MainActor.assumeIsolated { if self?.nm.hasMusic == true && self?.nm.playing == true { Task { await self?.nm.syncPosition() } } } },
    ]
    observer = DistributedNotificationCenter.default().addObserver(forName: .init("com.apple.Music.playerInfo"), object: nil, queue: .main) { [weak self] n in
      let info = n.userInfo ?? [:]
      MainActor.assumeIsolated { self?.nm.musicChanged(info) }
    }
    if lyrics { Task { await nm.syncPosition() } }
  }

  /** 浮层打开时先把歌词那行收起来，不挡浮层顶上的导航 */
  func overlay(_ visible: Bool, lyrics: Bool) {
    nm.showLyrics = lyrics && !visible
    nm.tick()
  }

  func pause() { for t in timers { t.fireDate = .distantFuture } }
  func resume() { for t in timers { t.fireDate = Date() } }

  private func stop() {
    for t in timers { t.invalidate() }
    timers = []
    if let observer { DistributedNotificationCenter.default().removeObserver(observer) }
    observer = nil
    window?.orderOut(nil)
    window?.contentView = nil
    window = nil
  }
}

struct NotchView: View {
  @ObservedObject var nm: NotchModel
  let notchW: CGFloat
  let barH: CGFloat

  var body: some View {
    let lyric = !nm.line.isEmpty
    VStack(spacing: 0) {
      HStack(spacing: 0) {
        HStack(spacing: 7) {
          if nm.hasMusic { Image(systemName: "waveform").font(.system(size: 10, weight: .bold)).foregroundStyle(nm.playing ? Color(hex: "#ff375f") : .white.opacity(0.45)) }
          meter("CPU", nm.cpu)
        }.frame(width: NotchWindow.wing).padding(.horizontal, 14)
        Spacer().frame(width: notchW - 28)
        meter("内存", nm.mem).frame(width: NotchWindow.wing, alignment: .trailing).padding(.horizontal, 14)
      }.frame(height: barH)
      if lyric {
        Text(nm.line).font(.system(size: nm.line.hasPrefix("♪") ? 12 : 13, weight: .medium)).foregroundStyle(.white.opacity(nm.line.hasPrefix("♪") ? 0.6 : 1))
          .lineLimit(1).truncationMode(.tail).padding(.horizontal, 18).frame(height: NotchWindow.lyricH - 4)
      }
    }
    .frame(width: notchW + 2 * NotchWindow.wing)
    .background(UnevenRoundedRectangle(bottomLeadingRadius: lyric ? 20 : 16, bottomTrailingRadius: lyric ? 20 : 16).fill(.black))
    .frame(maxHeight: .infinity, alignment: .top)
  }

  private func meter(_ label: String, _ v: Int?) -> some View {
    let x = v ?? 0
    let color: Color = x >= 85 ? Color(hex: "#ff453a") : x >= 60 ? Color(hex: "#ffd60a") : Color(hex: "#30d158")
    return HStack(spacing: 7) {
      Text(label).font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.55))
      ZStack(alignment: .leading) {
        Capsule().fill(.white.opacity(0.16)).frame(width: 38, height: 5)
        Capsule().fill(color).frame(width: 38 * CGFloat(x) / 100, height: 5)
      }
      Text(v.map { "\($0)%" } ?? "—").font(.system(size: 12, weight: .medium).monospacedDigit()).foregroundStyle(.white).frame(minWidth: 30, alignment: .trailing)
    }
  }
}
