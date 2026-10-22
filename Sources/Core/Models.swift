// 各个数据源整理好之后的样子。界面和管家规则都只认这些结构。
import Foundation

struct Quote: Equatable {
  var key: String
  var code: String
  var market: String          // cn / hk / us
  var index = false
  var name = ""
  var price: Double?
  var prev: Double?
  var open: Double?
  var high: Double?
  var low: Double?
  var ts: Double?             // 毫秒
  var chg: Double?
  var pct: Double?
  var failed = false
  var error: String?
  var status = "closed"       // live / closed / stale / fail
}

struct NewsItem: Equatable {
  var title: String
  var link: String
  var ts: Double
  var desc = ""
  var tag = ""
  var source = ""
}

struct NewsState {
  var items: [NewsItem] = []
  var error: String?
  var at: Double = 0
  var stale = false
}

struct WxNow { var temp: Int, feels: Int, humidity: Int, wind: Int, text: String, icon: String }
struct WxDay {
  var date: String
  var max: Int
  var min: Int
  var rain: Int?
  var text: String
  var icon: String
}

struct Weather {
  var city: String
  var at: Double
  var now: WxNow
  var days: [WxDay] = []
  var error: String?
  var stale = false
}

struct CalEvent: Equatable {
  var id: String
  var title: String
  var start: Double
  var end: Double
  var allDay = false
  var location = ""
  var calendar = ""
  var color: [Int]?
}

struct CalendarState {
  var ok: Bool
  var events: [CalEvent] = []
  var error: String?
  var needAuth = false
  var at: Double = 0
}

struct MailItem: Equatable {
  var name: String
  var email: String
  var subject: String
  var ts: Double?
  var id: String
  var account = ""
  var msgid = ""      // 邮件自己的 Message-ID（IMAP 邮箱在网页里打开那封信用）
}

struct MailState {
  var ok: Bool
  var unread = 0
  var items: [MailItem] = []
  var error: String?
  var notRunning = false
}

struct BatteryDevice: Equatable {
  var name: String
  var pct: Int
  var charging = false
  var charged = false
  var `internal` = false
  var ac = false
  var type = "other"          // laptop / headphones / mouse / keyboard / trackpad / speaker / other
}

struct QuantPosition {
  var code: String
  var name: String
  var shares: Double?
  var cost: Double?
  var price: Double?
  var pct: Double?
  var mv: Double?
  var pnl: Double?
  var pnlPct: Double?
  var dayPnl: Double?
  var tType = "none"
  var tMsg = ""
  var ma10: Double? = nil
  var ma20: Double? = nil
  var trend = ""
  var signal = ""
  var maxPrice: Double? = nil
  var trailPct: Double? = nil
  var kline: KLine? = nil
}

/** 量化系统的观察池 / 选股候选（只读；点「加自选」才进你的自选） */
struct QuantPick {
  var code: String
  var name: String
  var price: Double?
  var pct: Double?
  var ma10: Double? = nil
  var ma20: Double? = nil
  var trend = ""
  var signal = ""
  var strategy = ""
  var sector = ""
  var heat = ""
  var pe: Double? = nil
  var peg: Double? = nil
  var roe: Double? = nil
  var revGrow: Double? = nil
  var profitGrow: Double? = nil
  var mom60: Double? = nil
  var bias20: Double? = nil
}

struct QuantScan {
  var at = ""
  var mode = ""
  var regime = ""
  var universe: Double? = nil
  var prefiltered: Double? = nil
  var qualified: Double? = nil
  var candidates: [QuantPick] = []
}

struct QuantRisk {
  var status: String
  var drawdown: Double?
  var halfLine: Double?
  var exitLine: Double?
  var stopLoss: Double?
  var peak: Double? = nil
}

struct QuantAccount {
  var initial: Double?
  var total: Double?
  var pnl: Double?
  var pnlPct: Double?
  var dayPnl: Double
  var posRatio: Double?
  var cash: Double? = nil
  var mv: Double? = nil
}

struct QuantState {
  var ok = true
  var error: String?
  var running: Bool?
  var updatedAt: String?
  var positions: [QuantPosition] = []
  var risk: QuantRisk?
  var account: QuantAccount?
  var watchlist: [QuantPick] = []
  var scan: QuantScan? = nil
  var reports: [(date: String, path: String)] = []
  var dir = ""
}

/** 一条提醒（AI 提醒在第 4 阶段；这里只为了在管家组件里列出开着的那几条） */
struct ReminderLine { var time: String, title: String }
