// 入口：只开一个（再双击一次 = 打开浮层），托盘图标、全局快捷键 Ctrl+Alt+空格、每块屏幕的桌面层、Dock。
// Explorer 重启（任务栏重建）时自动重新放回桌面层。出错写进 %APPDATA%\DeskHub\error.log，不弹窗打扰。
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Threading;
using System.Windows;
using System.Windows.Interop;
using System.Windows.Media;
using DeskHub.Core;
using static DeskHub.Core.I18n;
using Forms = System.Windows.Forms;

namespace DeskHub;

public static class Program
{
    [STAThread]
    public static void Main(string[] args)
    {
        var snap = Array.IndexOf(args, "--snapshot");
        if (snap >= 0 && snap + 1 < args.Length)
        {
            string Arg(string k, string d) { var i = Array.IndexOf(args, k); return i >= 0 && i + 1 < args.Length ? args[i + 1] : d; }
            var lang = Arg("--lang", "zh");
            Strings.Lang = lang;
            _ = new Application();   // 让 pack:// 资源能用
            try { Snapshot.Run(args[snap + 1], lang, Arg("--theme", "light")); }
            catch (Exception e) { Directory.CreateDirectory(args[snap + 1]); File.WriteAllText(Path.Combine(args[snap + 1], "error.txt"), e.ToString()); }
            return;
        }
        using var quit = new EventWaitHandle(false, EventResetMode.AutoReset, "DeskHub.Quit");
        if (args.Contains("--quit")) { quit.Set(); return; }   // 卸载程序用：让正在运行的那个正常退出（会把桌面图标还回去）
        using var mutex = new Mutex(true, "DeskHub.SingleInstance", out var first);
        using var show = new EventWaitHandle(false, EventResetMode.AutoReset, "DeskHub.ShowOverlay");
        if (!first) { show.Set(); return; }   // 已经开着：让那个打开浮层
        var app = new App(args.Contains("--startup"));
        ThreadPool.RegisterWaitForSingleObject(show, (_, _) => app.Dispatcher.BeginInvoke(app.ToggleOverlay), null, -1, false);
        ThreadPool.RegisterWaitForSingleObject(quit, (_, _) => app.Dispatcher.BeginInvoke(() => app.Shutdown()), null, -1, true);
        app.Run();
    }
}

public class App : Application
{
    public static App Instance = null!;
    public static string Version => typeof(App).Assembly.GetName().Version is Version v ? $"{v.Major}.{v.Minor}.{v.Build}" : "0.0.0";

    public Model M = null!;
    readonly List<DeskWindow> desks = new();
    DockWindow? dock;
    Forms.NotifyIcon? tray;
    HwndSource? msg;
    uint taskbarCreated;
    readonly bool startup;

    public App(bool startup)
    {
        Instance = this;
        this.startup = startup;
        ShutdownMode = ShutdownMode.OnExplicitShutdown;
        DispatcherUnhandledException += (_, e) => { Log(e.Exception); e.Handled = true; };
        AppDomain.CurrentDomain.UnhandledException += (_, e) => Log(e.ExceptionObject as Exception);
        TaskScheduler_Unobserved();
    }

    static void TaskScheduler_Unobserved() =>
        System.Threading.Tasks.TaskScheduler.UnobservedTaskException += (_, e) => { Log(e.Exception); e.SetObserved(); };

    public static void Log(Exception? e)
    {
        try { File.AppendAllText(Path.Combine(Path.GetDirectoryName(Store.DefaultPath)!, "error.log"), $"[{DateTime.Now:yyyy-MM-dd HH:mm:ss}] {e}\n\n"); } catch { }
    }

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);
        M = new Model();
        M.Notify = (t, b) => tray?.ShowBalloonTip(5000, t, b, Forms.ToolTipIcon.None);
        M.Changed += keys =>
        {
            if (keys.Contains("lang")) BuildTrayMenu();
            if (keys.Contains("dock")) ApplyDock();
        };
        SetupTray();
        SetupHotkey();
        if (!M.Store.Onboarded)
        {
            var ob = new Onboarding(M) { Done = Launch };
            ob.Show();
        }
        else Launch();
    }

    void Launch()
    {
        RebuildDesks();
        ApplyDock();
        // 上次如果是被强行关掉的，桌面图标可能还藏着：按设置重新摆一次
        Native.SetDesktopIconsVisible(!M.Store.WinFlag("hideIcons", false));
        M.Start();
        if (!startup && M.Store.Onboarded && M.Store.Win["welcomed"] == null)
        {
            M.Store.SetWin("welcomed", true);
            tray?.ShowBalloonTip(6000, L("桌面信息中心已经在运行"), L("按 Ctrl + Alt + 空格 打开浮层；右下角托盘图标里有设置"), Forms.ToolTipIcon.None);
        }
    }

    protected override void OnExit(ExitEventArgs e)
    {
        Native.SetDesktopIconsVisible(true);   // 退出时把桌面图标还回去
        dock?.Close();                         // 顺便把 Dock 占的底部空间还给系统
        if (msg != null) Native.UnregisterHotKey(msg.Handle, 1);
        if (tray != null) { tray.Visible = false; tray.Dispose(); }
        base.OnExit(e);
    }

    // —— 屏幕 ——
    public static string KeyOf(Forms.Screen s) => s.Primary ? "main" : s.DeviceName;

    /** 底部要留出来的高度（逻辑像素）：任务栏 + 主屏上的 Dock */
    public static double BottomGap(Visual v, Forms.Screen s)
    {
        double scale = 1;
        try { scale = VisualTreeHelper.GetDpi(v).DpiScaleY; } catch { }
        var gap = (s.Bounds.Bottom - s.WorkingArea.Bottom) / scale;
        // Dock 占住了底部那一条时，WorkingArea 已经把它算进去了
        var dockOn = s.Primary && Instance.M.Store.WinFlag("dock", true) && !Instance.M.Store.WinFlag("dockAutoHide", false) && !Instance.DockReserved;
        return gap + (dockOn ? 84 : 0);
    }

    public void RebuildDesks()
    {
        foreach (var d in desks) { try { d.Close(); } catch { } }
        desks.Clear();
        var screens = Forms.Screen.AllScreens.Where(s => s.Primary || M.Store.WinFlag("allScreens", true)).ToList();
        M.ScreenKeys = screens.Select(KeyOf).ToList();
        var host = Native.FindDesktopHost();
        foreach (var s in screens)
        {
            try { desks.Add(new DeskWindow(M, s, KeyOf(s), host)); }
            catch (Exception e) { Log(e); }
        }
        M.Kick("all");
    }

    bool applyingDock;
    public void ApplyDock(bool reset = false)
    {
        if (applyingDock) return;   // 新建 Dock 时它会写默认应用，又会触发这里：防止开出两个
        applyingDock = true;
        try
        {
            var want = M.Store.WinFlag("dock", true);
            if (reset && dock != null) { dock.Close(); dock = null; }
            if (want && dock == null) { dock = new DockWindow(M); dock.Show(); }
            else if (!want && dock != null) { dock.Close(); dock = null; }
        }
        finally { applyingDock = false; }
    }

    public bool DockReserved => dock?.Reserved == true;

    /** Dock 占不占底部那一条变了：桌面层的组件要重新排（底部留白不一样了） */
    public void DockReservedChanged() => Dispatcher.BeginInvoke(() => { foreach (var d in desks) d.Relayout(); }, System.Windows.Threading.DispatcherPriority.Background);

    // —— 浮层、设置 ——
    public void ToggleOverlay()
    {
        if (OverlayWindow.Current != null) { OverlayWindow.Current.Close(); return; }
        if (!M.Store.Onboarded)
        {
            // 引导没走完就关了：再走一次
            if (!Windows.OfType<Onboarding>().Any()) new Onboarding(M) { Done = Launch }.Show();
            return;
        }
        Native.GetCursorPos(out var pt);
        var s = Forms.Screen.FromPoint(new System.Drawing.Point(pt.X, pt.Y));
        var key = M.ScreenKeys.Contains(KeyOf(s)) ? KeyOf(s) : "main";
        if (key == "main") s = Forms.Screen.PrimaryScreen ?? s;
        new OverlayWindow(M, s, key).Show();
    }

    SettingsWindow? settings;
    public void ShowSettings(string page = "general")
    {
        if (settings != null) { settings.Activate(); return; }
        settings = new SettingsWindow(M, page);
        settings.Closed += (_, _) => settings = null;
        settings.Show();
        settings.Activate();
    }

    // —— 托盘 ——
    void SetupTray()
    {
        tray = new Forms.NotifyIcon { Text = "DeskHub", Visible = true };
        try
        {
            var s = GetResourceStream(new Uri("pack://application:,,,/icon.ico"))?.Stream;
            tray.Icon = s != null ? new System.Drawing.Icon(s) : System.Drawing.SystemIcons.Application;
        }
        catch { tray.Icon = System.Drawing.SystemIcons.Application; }
        tray.MouseClick += (_, e) => { if (e.Button == Forms.MouseButtons.Left) ToggleOverlay(); };
        BuildTrayMenu();
    }

    void BuildTrayMenu()
    {
        if (tray == null) return;
        var menu = new Forms.ContextMenuStrip();
        menu.Items.Add(L("打开浮层") + "    Ctrl+Alt+Space", null, (_, _) => ToggleOverlay());
        menu.Items.Add(L("设置…"), null, (_, _) => ShowSettings());
        menu.Items.Add(new Forms.ToolStripSeparator());
        var hide = new Forms.ToolStripMenuItem(L("清空桌面（隐藏桌面图标）")) { Checked = M?.Store.WinFlag("hideIcons", false) == true };
        hide.Click += (_, _) => { var v = !M.Store.WinFlag("hideIcons", false); M.Store.SetWin("hideIcons", v); Native.SetDesktopIconsVisible(!v); BuildTrayMenu(); };
        menu.Items.Add(hide);
        var dk = new Forms.ToolStripMenuItem(L("显示底部 Dock")) { Checked = M?.Store.WinFlag("dock", true) != false };
        dk.Click += (_, _) => { M.Store.SetWin("dock", !M.Store.WinFlag("dock", true)); ApplyDock(); BuildTrayMenu(); };
        menu.Items.Add(dk);
        menu.Items.Add(L("重新放回桌面"), null, (_, _) => RebuildDesks());
        menu.Items.Add(new Forms.ToolStripSeparator());
        menu.Items.Add(L("检查更新"), null, (_, _) => UI.Open(Update.ReleasesPage));
        menu.Items.Add(L("退出"), null, (_, _) => Shutdown());
        tray.ContextMenuStrip = menu;
    }

    // —— 全局快捷键 + Explorer 重启 ——
    void SetupHotkey()
    {
        msg = new HwndSource(new HwndSourceParameters("DeskHubMessages") { Width = 0, Height = 0, WindowStyle = 0 });
        msg.AddHook(WndProc);
        taskbarCreated = Native.RegisterWindowMessage("TaskbarCreated");
        const uint MOD_ALT = 0x1, MOD_CONTROL = 0x2, MOD_NOREPEAT = 0x4000, VK_SPACE = 0x20;
        if (!Native.RegisterHotKey(msg.Handle, 1, MOD_CONTROL | MOD_ALT | MOD_NOREPEAT, VK_SPACE))
            Dispatcher.BeginInvoke(() => tray?.ShowBalloonTip(6000, L("快捷键被占用了"), L("Ctrl + Alt + 空格 已经被别的程序用了。可以点托盘图标打开浮层。"), Forms.ToolTipIcon.Warning));
    }

    IntPtr WndProc(IntPtr hwnd, int message, IntPtr w, IntPtr l, ref bool handled)
    {
        if (message == 0x0312 && w.ToInt32() == 1) { ToggleOverlay(); handled = true; }
        else if (taskbarCreated != 0 && message == (int)taskbarCreated)
        {
            // Explorer 重启了：桌面层要重新放一次，图标显示状态也要重新设
            Dispatcher.BeginInvoke(() =>
            {
                RebuildDesks();
                if (M.Store.WinFlag("hideIcons", false)) Native.SetDesktopIconsVisible(false);
                if (tray != null) { tray.Visible = false; tray.Visible = true; }
            });
        }
        else if (message == 0x007E /* WM_DISPLAYCHANGE */) Dispatcher.BeginInvoke(RebuildDesks);
        return IntPtr.Zero;
    }
}
