// 管家：把今天要紧的事挑三件说出来。规则和 Mac 版一样只陈述事实，不做建议：
//   马上要开始的日程 > 重要的人来信 > 带伞 > 今天的节日 > 待办 > 其他日程。
// 每条都标明来源，没有可说的就说一句「没什么要紧的」。
using System.Globalization;
using static DeskHub.Core.I18n;

namespace DeskHub.Core;

public record ButlerLine(string Icon, string Text, int Rank);

public class ButlerInputs
{
    public double Now = U.NowMs();
    public List<CalEvent> Events = new();
    public MailState? Mail;
    public List<string> Contacts = new();
    public Weather? Weather;
    public int OpenTodos;
    public int SoonMin = 15;
}

public static class Butler
{
    public static string Greeting(double now)
    {
        var h = U.Ymd(now).H;
        return h < 5 ? L("夜深了") : h < 11 ? L("早上好") : h < 13 ? L("中午好") : h < 18 ? L("下午好") : L("晚上好");
    }

    static string Hm(double ms) { var t = U.Ymd(ms); return $"{U.Pad2(t.H)}:{U.Pad2(t.Mi)}"; }

    public static List<ButlerLine> Lines(ButlerInputs x, int max = 3)
    {
        var o = new List<ButlerLine>();
        var t = U.Ymd(x.Now);
        double dayEnd = U.LocalMs(t.Y, t.M, t.D + 1);

        // 日程：进行中 / 马上开始 / 今天还有
        var upcoming = x.Events.Where(e => !e.AllDay && e.End > x.Now && e.Start < dayEnd).OrderBy(e => e.Start).ToList();
        if (upcoming.FirstOrDefault() is CalEvent ev)
        {
            var mins = (int)Math.Ceiling((ev.Start - x.Now) / 60000);
            if (mins <= 0) o.Add(new("calendar", L("「%@」正在进行，%@ 结束", ev.Title, Hm(ev.End)), 0));
            else if (mins <= x.SoonMin) o.Add(new("calendar", L("%@ 分钟后：%@", mins, ev.Title), 0));
            else o.Add(new("calendar", L("下一个日程 %@ %@", Hm(ev.Start), ev.Title) + (upcoming.Count > 1 ? L("（今天还有 %@ 个）", upcoming.Count - 1) : ""), 5));
        }

        // 邮件：重要联系人的来信排前面
        if (x.Mail is { Ok: true } m && m.Unread > 0)
        {
            var vip = m.Items.FirstOrDefault(i => x.Contacts.Any(c => c != "" && (i.Email.Contains(c, StringComparison.OrdinalIgnoreCase) || i.Name.Contains(c, StringComparison.OrdinalIgnoreCase))));
            if (vip != null) o.Add(new("mail", L("%@ 来信：%@", vip.Name, vip.Subject), 1));
            else o.Add(new("mail", L("%@ 封未读邮件", m.Unread), 6));
        }

        // 天气：今天下雨
        if (x.Weather?.Days.FirstOrDefault() is WxDay d && d.Rain is int rain && rain >= 50)
            o.Add(new("umbrella", L("今天降水概率 %@%%，记得带伞", rain), 2));

        // 节日
        if (Lunar.Festival(x.Now) is string f) o.Add(new("gift", L("今天是%@", L(f)), 3));

        if (x.OpenTodos > 0) o.Add(new("check", L("%@ 件待办没做完", x.OpenTodos), 4));

        return o.OrderBy(l => l.Rank).Take(max).ToList();
    }

    public static string Headline(ButlerInputs x, string name)
    {
        var lines = Lines(x, 1);
        return lines.Count == 0 ? Greeting(x.Now) + L("，今天没什么要紧的") : Greeting(x.Now);
    }
}
