// 系统状态（CPU、内存、磁盘、网速、电池）和「正在播放」。都直接读系统接口，不起外部命令。
import AppKit
import IOKit.ps

struct SysStat: Equatable {
  var cpu: Int?
  var mem: Int?
  var diskFree: Double?, diskTotal: Double?
  var up: Double = 0, down: Double = 0          // 字节 / 秒
  var battery: Int?, charging = false
}

/** CPU 用两次采样的差，网速也是：所以要留着上一次的数 */
final class SysSampler {
  private var lastCPU: (busy: UInt64, total: UInt64)?
  private var lastNet: (inB: UInt64, outB: UInt64, at: Date)?

  func cpu() -> Int? {
    var count: mach_msg_type_number_t = 0
    var info: processor_info_array_t?
    var n: natural_t = 0
    guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &n, &info, &count) == KERN_SUCCESS, let info else { return nil }
    var busy: UInt64 = 0, total: UInt64 = 0
    for i in 0..<Int(n) {
      let b = Int(CPU_STATE_MAX) * i
      let user = UInt64(info[b + Int(CPU_STATE_USER)]), sys = UInt64(info[b + Int(CPU_STATE_SYSTEM)])
      let nice = UInt64(info[b + Int(CPU_STATE_NICE)]), idle = UInt64(info[b + Int(CPU_STATE_IDLE)])
      busy += user + sys + nice
      total += user + sys + nice + idle
    }
    vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), vm_size_t(Int(count) * MemoryLayout<integer_t>.stride))
    defer { lastCPU = (busy, total) }
    guard let l = lastCPU, total > l.total else { return nil }
    return Int((Double(busy - l.busy) / Double(total - l.total) * 100).rounded())
  }

  /** 活跃 + 联动 + 被压缩占用（接近「活动监视器」的口径） */
  func mem() -> Int? {
    var stats = vm_statistics64()
    var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
    let r = withUnsafeMutablePointer(to: &stats) { $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count) } }
    guard r == KERN_SUCCESS else { return nil }
    var page: vm_size_t = 0
    host_page_size(mach_host_self(), &page)
    let used = Double(UInt64(stats.active_count) + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)) * Double(page)
    return min(100, Int((used / Double(ProcessInfo.processInfo.physicalMemory) * 100).rounded()))
  }

  /** 所有网卡（不含本机回环）收发字节的差 */
  func net() -> (up: Double, down: Double) {
    var ifa: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&ifa) == 0, let first = ifa else { return (0, 0) }
    defer { freeifaddrs(ifa) }
    var inB: UInt64 = 0, outB: UInt64 = 0
    var p: UnsafeMutablePointer<ifaddrs>? = first
    while let cur = p {
      let a = cur.pointee
      if a.ifa_addr?.pointee.sa_family == UInt8(AF_LINK), let d = a.ifa_data?.assumingMemoryBound(to: if_data.self), !String(cString: a.ifa_name).hasPrefix("lo") {
        inB += UInt64(d.pointee.ifi_ibytes); outB += UInt64(d.pointee.ifi_obytes)
      }
      p = a.ifa_next
    }
    let now = Date()
    defer { lastNet = (inB, outB, now) }
    guard let l = lastNet, now > l.at, inB >= l.inB, outB >= l.outB else { return (0, 0) }
    let dt = now.timeIntervalSince(l.at)
    return (Double(outB - l.outB) / dt, Double(inB - l.inB) / dt)
  }

  func sample() -> SysStat {
    var s = SysStat(cpu: cpu(), mem: mem())
    if let v = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey]) {
      s.diskFree = v.volumeAvailableCapacityForImportantUsage.map(Double.init); s.diskTotal = v.volumeTotalCapacity.map(Double.init)
    }
    (s.up, s.down) = net()
    let blob = IOPSCopyPowerSourcesInfo().takeRetainedValue()
    for ps in IOPSCopyPowerSourcesList(blob).takeRetainedValue() as [CFTypeRef] {
      guard let d = IOPSGetPowerSourceDescription(blob, ps)?.takeUnretainedValue() as? [String: Any], d["Type"] as? String == "InternalBattery" else { continue }
      s.battery = d["Current Capacity"] as? Int
      s.charging = (d["Is Charging"] as? Bool) == true
    }
    return s
  }

  static func speed(_ bps: Double) -> String {
    if bps >= 1_048_576 { return String(format: "%.1f MB/s", bps / 1_048_576) }
    if bps >= 1024 { return String(format: "%.0f KB/s", bps / 1024) }
    return String(format: "%.0f B/s", bps)
  }
  static func gb(_ b: Double?) -> String { b.map { String(format: "%.0f GB", $0 / 1e9) } ?? "—" }
}

// —— 正在播放：Apple Music 和 Spotify 换歌、暂停时会广播通知，平时不轮询 ——
struct NowPlaying: Equatable {
  var app = ""            // Music / Spotify
  var title = "", artist = "", album = ""
  var playing = false
  var duration: Double = 0
  var position: Double = 0
  var at = Date()
  func pos(_ now: Date = Date()) -> Double { min(duration > 0 ? duration : .greatestFiniteMagnitude, position + (playing ? now.timeIntervalSince(at) : 0)) }
}

extension DeskModel {
  /** 收到播放器的广播：更新歌名和状态；再用一次 AppleScript 对准进度（只在换歌、继续播放时） */
  func playerChanged(app: String, info: [AnyHashable: Any]) {
    let state = (info["Player State"] as? String ?? "").lowercased()
    if state == "stopped" || state.isEmpty { if nowPlaying?.app == app { nowPlaying = nil }; return }
    var np = nowPlaying?.app == app ? nowPlaying! : NowPlaying(app: app)
    np.title = info["Name"] as? String ?? np.title
    np.artist = info["Artist"] as? String ?? np.artist
    np.album = info["Album"] as? String ?? np.album
    np.playing = state == "playing"
    if let t = num(info["Total Time"]) { np.duration = t / 1000 } else if let t = num(info["Duration"]) { np.duration = t / 1000 }
    if let p = num(info["Playback Position"]) { np.position = p } else { np.position = np.pos() }
    np.at = Date()
    nowPlaying = np
  }

  /** 播放 / 暂停 / 上一首 / 下一首（第一次会弹「允许控制音乐」的权限框） */
  func playerCommand(_ cmd: String) {
    guard let app = nowPlaying?.app, ["playpause", "next track", "previous track"].contains(cmd) else { return }
    Task { _ = await Fetch.run("/usr/bin/osascript", ["-e", "tell application \"\(app)\" to \(cmd)"], timeout: 5) }
  }
}
