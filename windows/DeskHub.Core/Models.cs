// 各组件用到的数据。时间一律是毫秒（和 Mac 版、Electron 版一样）。
namespace DeskHub.Core;

public class Quote
{
    public string Key = "", Code = "", Market = "", Name = "";
    public bool Index, Failed;
    public double? Price, Prev, Open, High, Low, Chg, Pct, Ts;
}

public record NewsItem(string Title, string Link, double Ts, string Desc, string Tag, string Source);

public record WxNow(int Temp, int Feels, int Humidity, int Wind, string Text, string Icon);
public record WxDay(string Date, int Max, int Min, int? Rain, string Text, string Icon);
public record Weather(string City, double At, WxNow Now, List<WxDay> Days);

public record CalEvent(string Id, string Title, double Start, double End, bool AllDay, string Location, string Calendar);

public record MailItem(string Name, string Email, string Subject, double? Ts, string Id, string Account, string MsgId = "");

public class MailState
{
    public bool Ok;
    public string? Error;
    public int Unread;
    public List<MailItem> Items = new();
}

public record CoinQuote(string Id, double Price, double? Change);
public record RepoInfo(string Name, int Stars, int Forks, int Issues, int? Downloads);

public class TodoItem
{
    public string Id = Guid.NewGuid().ToString("N")[..8];
    public string Title = "";
    public bool Done;
    public string Due = "";   // 2026-10-25，可以空
}
