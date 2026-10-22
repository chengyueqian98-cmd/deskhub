// 日历订阅（.ics）、农历和节日。和 Mac 版 ICS.swift 对应。
// Windows 没有像 Mac「日历」App 那样谁都能读的系统日历，所以日程来自订阅链接：
// Google 日历「iCal 格式的私密地址」、Outlook 的发布链接、学校课表都行。
using System.Globalization;
using static DeskHub.Core.I18n;

namespace DeskHub.Core;

public static class ICS
{
    public class VEvent
    {
        public string Uid = "", Summary = "", Location = "";
        public double Start, End;
        public bool AllDay;
        public TimeZoneInfo Tz = TimeZoneInfo.Local;
        public Dictionary<string, string> RRule = new();
        public HashSet<double> ExDates = new();
        public double? RecurrenceId;
    }

    public static List<string> Unfold(string text)
    {
        var o = new List<string>();
        foreach (var line in text.Replace("\r\n", "\n").Split('\n'))
        {
            if ((line.StartsWith(' ') || line.StartsWith('\t')) && o.Count > 0) o[^1] += line[1..];
            else o.Add(line);
        }
        return o;
    }

    public static string Unescape(string s) =>
        s.Replace("\\n", " ").Replace("\\N", " ").Replace("\\,", ",").Replace("\\;", ";").Replace("\\\\", "\\");

    /** Windows 的时区名（"China Standard Time"）和 IANA 名（"Asia/Shanghai"）都认 */
    static TimeZoneInfo? FindZone(string? id)
    {
        if (string.IsNullOrEmpty(id)) return null;
        try { return TimeZoneInfo.FindSystemTimeZoneById(id); } catch { return null; }
    }

    public static (double ms, bool allDay)? Date(string v, string? tzid)
    {
        var m = v.Trim().Match("^(\\d{4})(\\d{2})(\\d{2})(?:T(\\d{2})(\\d{2})(\\d{2})?(Z)?)?$");
        if (m == null) return null;
        int y = int.Parse(m[1]!), mo = int.Parse(m[2]!), d = int.Parse(m[3]!);
        bool allDay = m[4] == null;
        int h = int.Parse(m[4] ?? "0"), mi = int.Parse(m[5] ?? "0"), s = int.Parse(m[6] ?? "0");
        if (allDay) return (U.LocalMs(y, mo, d), true);
        var tz = m[7] != null ? TimeZoneInfo.Utc : FindZone(tzid) ?? TimeZoneInfo.Local;
        return (U.ZoneMs(tz, y, mo, d, h, mi, s), false);
    }

    public static (string name, Dictionary<string, string> pars, string value)? Field(string line)
    {
        int colon = line.IndexOf(':');
        if (colon < 0) return null;
        var parts = line[..colon].Split(';');
        var pars = new Dictionary<string, string>();
        foreach (var p in parts.Skip(1)) { var kv = p.Split('='); if (kv.Length == 2) pars[kv[0].ToUpperInvariant()] = kv[1].Replace("\"", ""); }
        return (parts[0].ToUpperInvariant(), pars, line[(colon + 1)..]);
    }

    public static List<VEvent> Events(string text)
    {
        var o = new List<VEvent>();
        VEvent? cur = null;
        double? duration = null;
        foreach (var line in Unfold(text))
        {
            if (line.StartsWith("BEGIN:VEVENT")) { cur = new VEvent(); duration = null; continue; }
            if (line.StartsWith("END:VEVENT"))
            {
                if (cur != null)
                {
                    if (cur.End == 0) cur.End = cur.Start + (duration ?? (cur.AllDay ? 86400e3 : 3600e3));
                    o.Add(cur);
                }
                cur = null;
                continue;
            }
            if (cur == null || Field(line) is not var (name, pars, value)) continue;
            pars.TryGetValue("TZID", out var tzid);
            switch (name)
            {
                case "UID": cur.Uid = value; break;
                case "SUMMARY": cur.Summary = Unescape(value); break;
                case "LOCATION": cur.Location = Unescape(value); break;
                case "DTSTART":
                    if (Date(value, tzid) is var (ms, ad)) { cur.Start = ms; cur.AllDay = ad; }
                    if (FindZone(tzid) is TimeZoneInfo z) cur.Tz = z;
                    break;
                case "DTEND": if (Date(value, tzid) is var (e, _)) cur.End = e; break;
                case "DURATION": duration = ParseDuration(value); break;
                case "RRULE":
                    foreach (var kv in value.Split(';')) { var p = kv.Split('='); if (p.Length == 2) cur.RRule[p[0].ToUpperInvariant()] = p[1]; }
                    break;
                case "EXDATE":
                    foreach (var v in value.Split(',')) if (Date(v, tzid) is var (x, _)) cur.ExDates.Add(x);
                    break;
                case "RECURRENCE-ID": cur.RecurrenceId = Date(value, tzid)?.ms; break;
            }
        }
        return o;
    }

    /** PT1H30M / P1D → 毫秒 */
    public static double? ParseDuration(string s)
    {
        var m = s.Match("^-?P(?:(\\d+)W)?(?:(\\d+)D)?(?:T(?:(\\d+)H)?(?:(\\d+)M)?(?:(\\d+)S)?)?$");
        if (m == null) return null;
        double N(int i) => double.Parse(m[i] ?? "0", CultureInfo.InvariantCulture);
        return ((N(1) * 7 + N(2)) * 86400 + N(3) * 3600 + N(4) * 60 + N(5)) * 1000;
    }

    static readonly Dictionary<string, DayOfWeek> Weekdays = new()
    {
        ["SU"] = DayOfWeek.Sunday, ["MO"] = DayOfWeek.Monday, ["TU"] = DayOfWeek.Tuesday, ["WE"] = DayOfWeek.Wednesday,
        ["TH"] = DayOfWeek.Thursday, ["FR"] = DayOfWeek.Friday, ["SA"] = DayOfWeek.Saturday,
    };

    /** 把重复的日程在 [from, to) 里展开成一次一次的（按日程自己的时区算，夏令时也对） */
    public static List<double> Expand(VEvent e, double from, double to, int limit = 500)
    {
        var len = e.End - e.Start;
        if (!e.RRule.TryGetValue("FREQ", out var freq)) return e.Start + len > from && e.Start < to ? new List<double> { e.Start } : new List<double>();
        var tz = e.AllDay ? TimeZoneInfo.Local : e.Tz;
        int interval = Math.Max(1, int.TryParse(e.RRule.GetValueOrDefault("INTERVAL", "1"), out var iv) ? iv : 1);
        int? count = int.TryParse(e.RRule.GetValueOrDefault("COUNT", ""), out var cn) ? cn : null;
        double? until = null;
        if (e.RRule.TryGetValue("UNTIL", out var us) && Date(us, null) is var (um, _)) until = um + (us.Length == 8 ? 86400e3 - 1 : 0);
        var byday = e.RRule.GetValueOrDefault("BYDAY", "").Split(',').Where(x => x.Length >= 2 && Weekdays.ContainsKey(x[^2..])).Select(x => Weekdays[x[^2..]]).ToHashSet();
        var start = TimeZoneInfo.ConvertTime(DateTimeOffset.FromUnixTimeMilliseconds((long)e.Start), tz).DateTime;
        double Ms(DateTime local) => U.ZoneMs(tz, local.Year, local.Month, local.Day, local.Hour, local.Minute, local.Second);
        var o = new List<double>();
        int produced = 0;
        for (int step = 0; step < 3000 && produced < limit; step++)
        {
            int k = step * interval;
            DateTime b = freq switch { "WEEKLY" => start.AddDays(7 * k), "MONTHLY" => start.AddMonths(k), "YEARLY" => start.AddYears(k), _ => start.AddDays(k) };
            var dates = new List<DateTime> { b };
            if (freq == "WEEKLY" && byday.Count > 0)
            {
                var weekStart = b.Date.AddDays(-(((int)b.DayOfWeek + 6) % 7));   // 周一开头
                dates = Enumerable.Range(0, 7).Select(i => weekStart.AddDays(i)).Where(d => byday.Contains(d.DayOfWeek))
                    .Select(d => d.Add(start.TimeOfDay)).Where(d => d >= start).ToList();
            }
            bool done = false;
            foreach (var d in dates)
            {
                var ms = Ms(d);
                if (until != null && ms > until) { done = true; break; }
                if (count != null && produced >= count) { done = true; break; }
                produced++;
                if (ms >= to) { done = true; break; }
                if (ms + len > from && !e.ExDates.Contains(ms)) o.Add(ms);
            }
            if (done) break;
        }
        return o;
    }

    public static List<CalEvent> Parse(string text, double from, double to, string calendar)
    {
        var all = Events(text);
        var overrides = all.Where(e => e.RecurrenceId != null).ToList();
        var replaced = new Dictionary<string, HashSet<double>>();
        foreach (var ov in overrides) { if (!replaced.ContainsKey(ov.Uid)) replaced[ov.Uid] = new(); replaced[ov.Uid].Add(ov.RecurrenceId!.Value); }
        var o = new List<CalEvent>();
        foreach (var e in all.Where(e => e.RecurrenceId == null && e.Start > 0))
            foreach (var s in Expand(e, from, to))
                if (!(replaced.TryGetValue(e.Uid, out var set) && set.Contains(s)))
                    o.Add(new CalEvent($"{e.Uid}@{(long)s}", e.Summary == "" ? L("（无标题）") : e.Summary, s, s + (e.End - e.Start), e.AllDay, e.Location, calendar));
        foreach (var ov in overrides.Where(x => x.End > from && x.Start < to))
            o.Add(new CalEvent($"{ov.Uid}@{(long)ov.Start}", ov.Summary, ov.Start, ov.End, ov.AllDay, ov.Location, calendar));
        return o.OrderBy(x => x.Start).ToList();
    }

    /** webcal:// 开头的订阅链接换成 https:// */
    public static string Url(string s)
    {
        var t = s.Trim();
        return t.ToLowerInvariant().StartsWith("webcal://") ? "https://" + t[9..] : t;
    }
}

public static class Lunar
{
    static readonly string[] Months = { "正", "二", "三", "四", "五", "六", "七", "八", "九", "十", "冬", "腊" };
    static readonly string[] Tens = { "初", "十", "廿", "三" };
    static readonly string[] Digits = { "", "一", "二", "三", "四", "五", "六", "七", "八", "九", "十" };
    static readonly ChineseLunisolarCalendar Cal = new();

    /** 按「你这里的今天」算农历月、日、是否闰月 */
    public static (int month, int day, bool leap) Parts(double ms)
    {
        var t = U.Ymd(ms);
        var d = new DateTime(t.Y, t.M, t.D, 12, 0, 0);
        int y = Cal.GetYear(d), m = Cal.GetMonth(d), day = Cal.GetDayOfMonth(d);
        int leapM = Cal.GetLeapMonth(y);   // 闰月在这一年里排第几（0 = 没有闰月）
        bool leap = leapM > 0 && m == leapM;
        if (leapM > 0 && m >= leapM) m -= 1;
        return (m, day, leap);
    }

    public static string Text(double ms)
    {
        var p = Parts(ms);
        if (Strings.En) return $"Lunar {(p.leap ? "leap " : "")}{p.month}/{p.day}";
        int d = p.day;
        string day = d == 10 ? "初十" : d == 20 ? "二十" : d == 30 ? "三十" : Tens[d / 10] + Digits[d % 10];
        return (p.leap ? "闰" : "") + Months[p.month - 1] + "月" + day;
    }

    static readonly (int m, int d, string name)[] LunarFestivals = { (1, 1, "春节"), (1, 15, "元宵节"), (5, 5, "端午节"), (7, 7, "七夕"), (8, 15, "中秋节"), (9, 9, "重阳节"), (12, 8, "腊八") };
    static readonly (int m, int d, string name)[] SolarFestivals = { (1, 1, "元旦"), (2, 14, "情人节"), (5, 1, "劳动节"), (6, 1, "儿童节"), (10, 1, "国庆节"), (12, 25, "圣诞节") };

    public static int Qingming(int year) => (int)((year % 100) * 0.2422 + 4.81) - (year % 100) / 4;

    public static string? Festival(double ms)
    {
        var t = U.Ymd(ms);
        foreach (var f in SolarFestivals) if (f.m == t.M && f.d == t.D) return f.name;
        if (t.M == 4 && t.D == Qingming(t.Y)) return "清明";
        var p = Parts(ms);
        if (!p.leap) foreach (var f in LunarFestivals) if (f.m == p.month && f.d == p.day) return f.name;
        var tm = Parts(U.LocalMs(t.Y, t.M, t.D + 1, 12));
        if (tm.month == 1 && tm.day == 1 && !tm.leap) return "除夕";
        return null;
    }

    public static (string name, int days)? Next(double? now = null, int within = 400)
    {
        var t = U.Ymd(now ?? U.NowMs());
        for (int i = 0; i < within; i++)
            if (Festival(U.LocalMs(t.Y, t.M, t.D + i, 12)) is string f) return (f, i);
        return null;
    }
}
