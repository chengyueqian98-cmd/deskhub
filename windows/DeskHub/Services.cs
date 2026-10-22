// 联网和系统服务：网络请求、密码保险箱（DPAPI）、IMAP 收信、系统负载、正在播放、DeepSeek、开机启动。
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Net.Http;
using System.Net.NetworkInformation;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json.Nodes;
using System.Threading;
using System.Threading.Tasks;
using DeskHub.Core;
using MailKit;
using MailKit.Net.Imap;
using MailKit.Search;
using Microsoft.Win32;
using static DeskHub.Core.I18n;

namespace DeskHub;

static class Net
{
    public static readonly HttpClient Http = Make();

    static HttpClient Make()
    {
        Encoding.RegisterProvider(CodePagesEncodingProvider.Instance);
        var h = new HttpClient { Timeout = TimeSpan.FromSeconds(15) };
        h.DefaultRequestHeaders.UserAgent.ParseAdd("Mozilla/5.0 DeskHub/" + App.Version + " (Windows)");
        return h;
    }

    public static async Task<byte[]> Bytes(string url, string? referer = null)
    {
        using var req = new HttpRequestMessage(HttpMethod.Get, url);
        if (referer != null) req.Headers.Referrer = new Uri(referer);
        using var res = await Http.SendAsync(req);
        res.EnsureSuccessStatusCode();
        return await res.Content.ReadAsByteArrayAsync();
    }

    public static async Task<string> Text(string url, string? referer = null, Encoding? enc = null) =>
        (enc ?? Encoding.UTF8).GetString(await Bytes(url, referer));

    public static async Task<JsonNode?> Json(string url) => JsonNode.Parse(await Text(url));

    public static Encoding Gbk => Encoding.GetEncoding("GB18030");
}

/** 密码和 API Key：用 Windows 自带的 DPAPI 加密（只有你这个 Windows 账户能解开），单独存一个文件，不进设置文件 */
static class Secrets
{
    static string PathFor => System.IO.Path.Combine(System.IO.Path.GetDirectoryName(Store.DefaultPath)!, "secrets.dat");

    static JsonObject Load()
    {
        try { return JsonNode.Parse(File.ReadAllText(PathFor)) as JsonObject ?? new JsonObject(); } catch { return new JsonObject(); }
    }

    public static string? Get(string key)
    {
        try
        {
            if (U.Str(Load()[key]) is not string b64) return null;
            return Encoding.UTF8.GetString(ProtectedData.Unprotect(Convert.FromBase64String(b64), null, DataProtectionScope.CurrentUser));
        }
        catch { return null; }
    }

    public static void Set(string key, string? value)
    {
        var all = Load();
        if (string.IsNullOrEmpty(value)) all.Remove(key);
        else all[key] = Convert.ToBase64String(ProtectedData.Protect(Encoding.UTF8.GetBytes(value), null, DataProtectionScope.CurrentUser));
        Directory.CreateDirectory(System.IO.Path.GetDirectoryName(PathFor)!);
        File.WriteAllText(PathFor, all.ToJsonString());
    }
}

/** IMAP 收信（只读：用只读方式打开收件箱，不会标成已读，也不会改、删、发任何东西） */
static class ImapMail
{
    public record Account(string Email, MailProvider Provider, string Host, int Port);

    public static Account? From(Store s)
    {
        var m = s.Mail;
        if (U.Str(m["source"]) != "imap" || U.Str(m["email"]) is not string email || email == "") return null;
        var p = MailProviders.By(U.Str(m["provider"]) ?? MailProviders.Guess(email));
        var host = U.Str(m["host"]) is string h && h != "" ? h : p.Host;
        return new Account(email, p, host, (int)(U.Num(m["port"]) ?? p.Port));
    }

    public static string SecretKey(string email) => "mail:" + email.ToLowerInvariant();

    static async Task<ImapClient> Login(Account a, CancellationToken ct)
    {
        var pass = Secrets.Get(SecretKey(a.Email)) ?? throw new Exception(L("还没填邮箱的应用专用密码：到「设置 → 邮件」里填"));
        if (a.Host == "") throw new Exception(L("还没填 IMAP 服务器地址"));
        var c = new ImapClient { Timeout = 15000 };
        try
        {
            await c.ConnectAsync(a.Host, a.Port, MailKit.Security.SecureSocketOptions.SslOnConnect, ct);
            // 网易邮箱要求先报一下客户端身份
            if (c.Capabilities.HasFlag(ImapCapabilities.Id)) { try { await c.IdentifyAsync(new ImapImplementation { Name = "DeskHub", Version = App.Version }, ct); } catch { } }
            try { await c.AuthenticateAsync(a.Email, pass, ct); }
            catch (Exception e) { throw new Exception(L("邮箱登录失败：大多数邮箱要用「应用专用密码 / 授权码」，不是网页登录密码。") + $" ({e.Message})"); }
            await c.Inbox.OpenAsync(FolderAccess.ReadOnly, ct);
            return c;
        }
        catch { c.Dispose(); throw; }
    }

    public static async Task<MailState> Unread(Account a, int limit = 12)
    {
        try
        {
            using var cts = new CancellationTokenSource(30000);
            using var c = await Login(a, cts.Token);
            var uids = await c.Inbox.SearchAsync(SearchQuery.NotSeen, cts.Token);
            var pick = uids.Skip(Math.Max(0, uids.Count - limit)).ToList();
            var items = new List<MailItem>();
            if (pick.Count > 0)
            {
                foreach (var s in await c.Inbox.FetchAsync(pick, MessageSummaryItems.Envelope | MessageSummaryItems.UniqueId, cts.Token))
                {
                    var from = s.Envelope.From.Mailboxes.FirstOrDefault();
                    items.Add(new MailItem(string.IsNullOrEmpty(from?.Name) ? from?.Address ?? "" : from!.Name, from?.Address ?? "",
                        string.IsNullOrEmpty(s.Envelope.Subject) ? MailProviders.NoSubject : s.Envelope.Subject,
                        s.Envelope.Date?.ToUnixTimeMilliseconds(), "imap:" + s.UniqueId.Id, a.Provider.Name, s.Envelope.MessageId ?? ""));
                }
            }
            await c.DisconnectAsync(true, cts.Token);
            return new MailState { Ok = true, Unread = uids.Count, Items = items.OrderByDescending(i => i.Ts ?? 0).ToList() };
        }
        catch (Exception e) { return new MailState { Ok = false, Error = e.Message }; }
    }

    public record Body(string Name, string Email, string Subject, string Text);

    public static async Task<(Body? body, string? error)> Read(Account a, uint uid)
    {
        try
        {
            using var cts = new CancellationTokenSource(30000);
            using var c = await Login(a, cts.Token);
            var m = await c.Inbox.GetMessageAsync(new UniqueId(uid), cts.Token);
            await c.DisconnectAsync(true, cts.Token);
            var from = m.From.Mailboxes.FirstOrDefault();
            var text = m.TextBody ?? StripHtml(m.HtmlBody ?? "");
            text = text.Replace("\r\n", "\n").Rx("[ \\t]+\n", "\n").Rx("\n{3,}", "\n\n").Trim();
            return (new Body(from?.Name ?? from?.Address ?? "", from?.Address ?? "", m.Subject ?? MailProviders.NoSubject, text.Head(8000)), null);
        }
        catch (Exception e) { return (null, e.Message); }
    }

    static string StripHtml(string h) =>
        News.Decode(h.Rx("(?is)<(script|style)[^>]*>.*?</\\1>", "").Rx("(?i)<br\\s*/?>|</p>|</div>|</tr>", "\n"));

    public static async Task<string?> Test(Account a)
    {
        try { using var c = await Login(a, new CancellationTokenSource(20000).Token); await c.DisconnectAsync(true); return null; }
        catch (Exception e) { return e.Message; }
    }
}

/** CPU、内存、磁盘、网速、电量 */
public class SysStat
{
    public int? Cpu, Mem, Battery;
    public double? DiskFree, DiskTotal;
    public double Down, Up;
    public bool Charging;
}

class SysSampler
{
    long lastIdle, lastTotal, lastRx, lastTx;
    DateTime lastNet = DateTime.MinValue;

    public SysStat Sample()
    {
        var s = new SysStat();
        try
        {
            if (Native.GetSystemTimes(out var idle, out var kernel, out var user))
            {
                long total = kernel + user;   // kernel 里已经包含 idle
                if (lastTotal > 0 && total > lastTotal) s.Cpu = (int)Math.Round(100.0 * (1 - (double)(idle - lastIdle) / (total - lastTotal)));
                lastIdle = idle; lastTotal = total;
            }
        }
        catch { }
        try { var m = new Native.MEMORYSTATUSEX { dwLength = 64 }; if (Native.GlobalMemoryStatusEx(ref m)) s.Mem = (int)m.dwMemoryLoad; } catch { }
        try
        {
            var d = new DriveInfo(Path.GetPathRoot(Environment.SystemDirectory) ?? "C:\\");
            s.DiskFree = d.AvailableFreeSpace; s.DiskTotal = d.TotalSize;
        }
        catch { }
        try
        {
            long rx = 0, tx = 0;
            foreach (var n in NetworkInterface.GetAllNetworkInterfaces())
            {
                if (n.OperationalStatus != OperationalStatus.Up || n.NetworkInterfaceType == NetworkInterfaceType.Loopback) continue;
                var st = n.GetIPStatistics();
                rx += st.BytesReceived; tx += st.BytesSent;
            }
            var now = DateTime.UtcNow;
            var dt = (now - lastNet).TotalSeconds;
            if (lastNet != DateTime.MinValue && dt > 0) { s.Down = Math.Max(0, (rx - lastRx) / dt); s.Up = Math.Max(0, (tx - lastTx) / dt); }
            lastRx = rx; lastTx = tx; lastNet = now;
        }
        catch { }
        try
        {
            var ps = System.Windows.Forms.SystemInformation.PowerStatus;
            if (!ps.BatteryChargeStatus.HasFlag(System.Windows.Forms.BatteryChargeStatus.NoSystemBattery) && ps.BatteryLifePercent <= 1)
            {
                s.Battery = (int)Math.Round(ps.BatteryLifePercent * 100);
                s.Charging = ps.PowerLineStatus == System.Windows.Forms.PowerLineStatus.Online;
            }
        }
        catch { }
        return s;
    }

    public static string Gb(double b) => b >= 1e12 ? $"{b / 1e12:0.0} TB" : $"{b / 1e9:0} GB";
    public static string Speed(double b) => b >= 1e6 ? $"{b / 1e6:0.0} MB/s" : b >= 1e3 ? $"{b / 1e3:0} KB/s" : $"{b:0} B/s";
}

/** 正在播放：Windows 的系统媒体控制，Spotify、网易云、QQ 音乐、浏览器里的视频都能看到 */
public class NowPlaying
{
    public string Title = "", Artist = "", App = "";
    public bool Playing;
    public double Position, Duration;
    public DateTime At = DateTime.UtcNow;
    public byte[]? Art;
    public double Pos(DateTime now) => Playing ? Math.Min(Duration, Position + (now - At).TotalSeconds) : Position;
}

static class Media
{
    static Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager? mgr;
    static string lastArtKey = "";
    static byte[]? lastArt;

    static async Task<Windows.Media.Control.GlobalSystemMediaTransportControlsSession?> Session()
    {
        mgr ??= await Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager.RequestAsync();
        return mgr.GetCurrentSession();
    }

    public static async Task<NowPlaying?> Current()
    {
        try
        {
            var s = await Session();
            if (s == null) return null;
            var props = await s.TryGetMediaPropertiesAsync();
            if (props == null || string.IsNullOrEmpty(props.Title)) return null;
            var tl = s.GetTimelineProperties();
            var pb = s.GetPlaybackInfo();
            var app = s.SourceAppUserModelId ?? "";
            app = app.Contains('!') ? app[(app.LastIndexOf('!') + 1)..] : app;
            app = app.EndsWith(".exe", StringComparison.OrdinalIgnoreCase) ? app[..^4] : app;
            var np = new NowPlaying
            {
                Title = props.Title, Artist = props.Artist ?? "", App = app,
                Playing = pb.PlaybackStatus == Windows.Media.Control.GlobalSystemMediaTransportControlsSessionPlaybackStatus.Playing,
                Position = tl.Position.TotalSeconds, Duration = (tl.EndTime - tl.StartTime).TotalSeconds,
                At = tl.LastUpdatedTime.UtcDateTime == default ? DateTime.UtcNow : tl.LastUpdatedTime.UtcDateTime,
            };
            var key = np.Title + "|" + np.Artist;
            if (key != lastArtKey && props.Thumbnail != null)
            {
                try
                {
                    using var st = await props.Thumbnail.OpenReadAsync();
                    using var ms = new MemoryStream();
                    await st.AsStreamForRead().CopyToAsync(ms);
                    lastArt = ms.ToArray();
                }
                catch { lastArt = null; }
                lastArtKey = key;
            }
            np.Art = key == lastArtKey ? lastArt : null;
            return np;
        }
        catch { return null; }
    }

    public static async Task Command(string cmd)
    {
        try
        {
            var s = await Session();
            if (s == null) return;
            if (cmd == "next") await s.TrySkipNextAsync();
            else if (cmd == "prev") await s.TrySkipPreviousAsync();
            else await s.TryTogglePlayPauseAsync();
        }
        catch { }
    }
}

/** DeepSeek（OpenAI 兼容接口）。Key 由用户自己在设置里填，存在 DPAPI 保险箱 */
static class DeepSeek
{
    public const string SecretKey = "deepseek";
    public const string KeyPage = "https://platform.deepseek.com/api_keys";

    public static bool HasKey => !string.IsNullOrEmpty(Secrets.Get(SecretKey));

    public static async Task<string> Ask(string system, IEnumerable<(string role, string content)> messages)
    {
        var key = Secrets.Get(SecretKey);
        if (string.IsNullOrEmpty(key)) return L("还没填 DeepSeek API Key：到「设置 → AI」里填");
        var msgs = new JsonArray { new JsonObject { ["role"] = "system", ["content"] = system } };
        foreach (var (r, c) in messages.TakeLast(12)) msgs.Add(new JsonObject { ["role"] = r, ["content"] = c });
        var body = new JsonObject { ["model"] = "deepseek-chat", ["messages"] = msgs, ["stream"] = false };
        using var req = new HttpRequestMessage(HttpMethod.Post, "https://api.deepseek.com/chat/completions")
        {
            Content = new StringContent(body.ToJsonString(), Encoding.UTF8, "application/json"),
        };
        req.Headers.Authorization = new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", key);
        try
        {
            using var cts = new CancellationTokenSource(60000);
            using var res = await Net.Http.SendAsync(req, cts.Token);
            var text = await res.Content.ReadAsStringAsync();
            if ((int)res.StatusCode == 401) return L("DeepSeek API Key 不对：到「设置 → AI」里重新填");
            if ((int)res.StatusCode == 402) return L("DeepSeek 账户余额不足：去 platform.deepseek.com 充值后再试");
            if (!res.IsSuccessStatusCode) return L("DeepSeek 出错了：") + (int)res.StatusCode;
            return U.Str(JsonNode.Parse(text)?["choices"]?[0]?["message"]?["content"])?.Trim() ?? "";
        }
        catch (Exception e) { return L("连不上 DeepSeek：") + e.Message; }
    }
}

static class AutoStart
{
    const string RunKey = @"Software\Microsoft\Windows\CurrentVersion\Run";

    public static bool Enabled
    {
        get { try { using var k = Registry.CurrentUser.OpenSubKey(RunKey); return k?.GetValue("DeskHub") != null; } catch { return false; } }
        set
        {
            try
            {
                using var k = Registry.CurrentUser.CreateSubKey(RunKey);
                if (value) k.SetValue("DeskHub", $"\"{Environment.ProcessPath}\" --startup");
                else k.DeleteValue("DeskHub", false);
            }
            catch { }
        }
    }
}
