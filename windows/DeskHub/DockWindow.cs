// 底部 Dock：像 Mac 那样放常用的应用和文件。左边是应用，右边是文件、下载文件夹和回收站。
// 把任何程序、快捷方式、文件、文件夹拖上来就能放进去；右键可以挪位置、移除。
// 右端的小箭头能把它收起来，收起后只剩底部一条小横线，鼠标碰一下就展开；也可以设成「自动收起」。
// 前台有全屏程序（看视频、打游戏）时自动让开。
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json.Nodes;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Threading;
using DeskHub.Core;
using static DeskHub.Core.I18n;

namespace DeskHub;

public class DockWindow : Window
{
    readonly Model m;
    readonly Action<HashSet<string>> onChanged;
    bool reserved;
    Native.RECT band;
    uint abMsg;
    readonly DispatcherTimer watch = new() { Interval = TimeSpan.FromSeconds(1) };
    DateTime leftAt = DateTime.MaxValue;
    bool collapsed, hiddenForFullscreen;
    Popup? stack;

    static string Downloads => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "Downloads");
    double IconSize => (U.Str(m.Store.Win["dockSize"]) ?? "M") switch { "S" => 38, "L" => 58, _ => 48 };
    bool AutoHide => m.Store.WinFlag("dockAutoHide", false);

    public DockWindow(Model m)
    {
        this.m = m;
        WindowStyle = WindowStyle.None;
        AllowsTransparency = true;
        Background = Brushes.Transparent;
        ResizeMode = ResizeMode.NoResize;
        ShowInTaskbar = false;
        ShowActivated = false;
        Topmost = true;
        SizeToContent = SizeToContent.WidthAndHeight;
        Title = "Glancedesk Dock";
        AllowDrop = true;
        Drop += OnDrop;
        collapsed = m.Store.WinFlag("dockCollapsed", false);
        Build();
        var hwnd = Native.Hwnd(this);
        Native.AddExStyle(hwnd, Native.WS_EX_TOOLWINDOW | Native.WS_EX_NOACTIVATE);
        SizeChanged += (_, _) => Place();
        MouseEnter += (_, _) => { leftAt = DateTime.MaxValue; if (collapsed) SetCollapsed(false, save: false); };
        MouseLeave += (_, _) => leftAt = DateTime.Now;
        watch.Tick += (_, _) => Watch();
        watch.Start();
        Microsoft.Win32.SystemEvents.DisplaySettingsChanged += OnDisplay;
        Closed += (_, _) => { watch.Stop(); Microsoft.Win32.SystemEvents.DisplaySettingsChanged -= OnDisplay; };
        onChanged = keys => { if (keys.Contains("theme") || keys.Contains("lang") || keys.Contains("dock")) Build(); };
        m.Changed += onChanged;
        Closed += (_, _) => { m.Changed -= onChanged; Reserve(false); };
        var src = System.Windows.Interop.HwndSource.FromHwnd(hwnd);
        abMsg = Native.RegisterWindowMessage("GlancedeskAppBar");
        src?.AddHook((IntPtr h, int msg, IntPtr w, IntPtr l, ref bool handled) =>
        {
            // 任务栏挪了位置、改了大小：重新占一次位置
            if (msg == (int)abMsg && w.ToInt32() == 1) Dispatcher.BeginInvoke(() => { if (reserved) { Reserve(true); Place(); } });
            return IntPtr.Zero;
        });
        // 第一次用：放几个常用的
        if (m.Store.Win["dockApps"] == null) SaveList("dockApps", DefaultApps());
    }

    void OnDisplay(object? s, EventArgs e) => Dispatcher.BeginInvoke(Place);

    double Scale { get { try { return VisualTreeHelper.GetDpi(this).DpiScaleY; } catch { return 1; } } }

    /** Dock 露出来的那一条有多高（逻辑像素） */
    double BandHeight => IconSize + 28;

    /** 像 Mac 一样占住屏幕底部这一条：最大化的窗口会让开，不会被 Dock 挡住。收起、自动收起时不占 */
    void Reserve(bool on)
    {
        try
        {
            var hwnd = new System.Windows.Interop.WindowInteropHelper(this).Handle;
            if (hwnd == IntPtr.Zero) return;
            var abd = new Native.APPBARDATA { cbSize = System.Runtime.InteropServices.Marshal.SizeOf<Native.APPBARDATA>(), hWnd = hwnd };
            if (!on)
            {
                if (reserved) { Native.SHAppBarMessage(1 /* ABM_REMOVE */, ref abd); reserved = false; App.Instance.DockReservedChanged(); }
                return;
            }
            var first = !reserved;
            if (first) { abd.uCallbackMessage = abMsg; Native.SHAppBarMessage(0 /* ABM_NEW */, ref abd); reserved = true; }
            var scr = (System.Windows.Forms.Screen.PrimaryScreen ?? System.Windows.Forms.Screen.AllScreens[0]).Bounds;
            int h = (int)Math.Ceiling(BandHeight * Scale);
            abd.uEdge = 3; // ABE_BOTTOM
            abd.rc = new Native.RECT { Left = scr.Left, Right = scr.Right, Top = scr.Bottom - h, Bottom = scr.Bottom };
            Native.SHAppBarMessage(2 /* ABM_QUERYPOS */, ref abd);
            abd.rc.Top = abd.rc.Bottom - h;
            Native.SHAppBarMessage(3 /* ABM_SETPOS */, ref abd);
            band = abd.rc;
            if (first) App.Instance.DockReservedChanged();
        }
        catch { }
    }

    public bool Reserved => reserved;

    void Place()
    {
        var want = !collapsed && !AutoHide && IsVisible;
        if (want != reserved) Reserve(want);
        var scr = (System.Windows.Forms.Screen.PrimaryScreen ?? System.Windows.Forms.Screen.AllScreens[0]);
        var k = Scale;
        if (reserved)
        {
            Left = (scr.Bounds.Left + scr.Bounds.Width / 2.0) / k - ActualWidth / 2;
            Top = band.Bottom / k - ActualHeight;
            return;
        }
        var wa = SystemParameters.WorkArea;
        Left = wa.Left + (wa.Width - ActualWidth) / 2;
        Top = wa.Bottom - ActualHeight - (collapsed ? 0 : 6);
    }

    /** 每秒看一眼：全屏程序在前台就藏起来；自动收起 */
    void Watch()
    {
        var ours = Application.Current.Windows.OfType<Window>().Select(w => new System.Windows.Interop.WindowInteropHelper(w).Handle);
        var fs = Native.ForegroundIsFullscreen(ours);
        if (fs != hiddenForFullscreen)
        {
            hiddenForFullscreen = fs;
            if (fs) Hide(); else Show();
        }
        if (AutoHide && !collapsed && !IsMouseOver && stack?.IsOpen != true && (DateTime.Now - leftAt).TotalSeconds > 1.2) SetCollapsed(true, save: false);
    }

    void SetCollapsed(bool v, bool save = true)
    {
        collapsed = v;
        if (save) m.Store.SetWin("dockCollapsed", v);
        Build();
    }

    List<string> List(string k) => U.Strs(m.Store.Win[k]);
    void SaveList(string k, IEnumerable<string> xs) { m.Store.SetWin(k, U.Arr(xs)); Build(); }

    // —— 画 Dock ——
    void Build()
    {
        var p = m.Pal;
        if (collapsed)
        {
            // 收起：底部一条小横线（留一点透明区域方便鼠标碰到）
            var line = new Border { Width = 96, Height = 5, CornerRadius = new CornerRadius(3), Background = p.Text3, VerticalAlignment = VerticalAlignment.Bottom, HorizontalAlignment = HorizontalAlignment.Center, Margin = new Thickness(0, 0, 0, 4) };
            Content = new Border { Width = 220, Height = 18, Background = new SolidColorBrush(Color.FromArgb(1, 0, 0, 0)), Child = line, ToolTip = L("展开 Dock") };
            Dispatcher.BeginInvoke(Place, DispatcherPriority.Loaded);
            return;
        }
        var row = new StackPanel { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Bottom };
        foreach (var path in List("dockApps")) row.Children.Add(Item(path, "dockApps"));
        row.Children.Add(Tile(G.Add, L("添加应用"), (_, _) => new AppPicker(m, add => SaveList("dockApps", List("dockApps").Append(add).Distinct())).Show(), small: true));
        row.Children.Add(Divider());
        foreach (var path in List("dockFiles")) row.Children.Add(Item(path, "dockFiles"));
        if (Directory.Exists(Downloads)) row.Children.Add(DownloadsStack());
        row.Children.Add(Tile(G.Recycle, L("回收站"), (_, _) => Launch("shell:RecycleBinFolder")));
        row.Children.Add(Tile(G.Down, L("收起 Dock"), (_, _) => SetCollapsed(true), small: true));

        var panel = new Border
        {
            Child = row, Background = p.Card, BorderBrush = p.CardBorder, BorderThickness = new Thickness(1), CornerRadius = new CornerRadius(20),
            Padding = new Thickness(8, 6, 8, 6), Effect = UI.Shadow(22, 0.22), Margin = new Thickness(16, IconSize * 0.4 + 6, 16, 12),
        };
        Content = panel;
        Dispatcher.BeginInvoke(Place, DispatcherPriority.Loaded);
    }

    FrameworkElement Divider() => new Border { Width = 1, Height = IconSize * 0.75, Background = m.Pal.Fill2, Margin = new Thickness(8, 0, 8, 0), VerticalAlignment = VerticalAlignment.Center };

    /** 一个应用或文件 */
    FrameworkElement Item(string path, string list)
    {
        var name = Path.GetFileNameWithoutExtension(path.TrimEnd('\\'));
        if (name == "") name = path;
        var img = Native.FileIcon(path);
        FrameworkElement icon = img != null
            ? new Image { Source = img, Width = IconSize, Height = IconSize }
            : new Border { Width = IconSize, Height = IconSize, CornerRadius = new CornerRadius(12), Background = m.Pal.Fill2, Child = UI.Icon(G.Doc, IconSize * 0.45, m.Pal.Text2) };
        var host = Magnify(icon, name);
        host.MouseLeftButtonUp += (_, _) => Launch(path);
        var menu = new ContextMenu();
        void Add(string text, Action a) { var mi = new MenuItem { Header = text }; mi.Click += (_, _) => a(); menu.Items.Add(mi); }
        Add(L("打开"), () => Launch(path));
        Add(L("在资源管理器中显示"), () => Launch("explorer.exe", $"/select,\"{path}\""));
        Add(L("往左挪"), () => MoveItem(list, path, -1));
        Add(L("往右挪"), () => MoveItem(list, path, 1));
        menu.Items.Add(new Separator());
        Add(L("从 Dock 移除"), () => SaveList(list, List(list).Where(x => x != path)));
        menu.Items.Add(new Separator());
        Add(m.Store.WinFlag("dockAutoHide", false) ? L("关掉自动收起") : L("自动收起"), () => { m.Store.SetWin("dockAutoHide", !AutoHide); });
        host.ContextMenu = menu;
        if (!File.Exists(path) && !Directory.Exists(path)) host.Opacity = 0.4;
        return host;
    }

    void MoveItem(string list, string path, int d)
    {
        var xs = List(list);
        int i = xs.IndexOf(path), j = i + d;
        if (i < 0 || j < 0 || j >= xs.Count) return;
        (xs[i], xs[j]) = (xs[j], xs[i]);
        SaveList(list, xs);
    }

    /** 用字形画的图标（添加、回收站、收起） */
    FrameworkElement Tile(string glyph, string tip, MouseButtonEventHandler click, bool small = false)
    {
        var s = small ? IconSize * 0.62 : IconSize;
        var b = new Border { Width = s, Height = s, CornerRadius = new CornerRadius(s * 0.24), Background = small ? Brushes.Transparent : m.Pal.Fill2, Child = UI.Icon(glyph, s * 0.42, m.Pal.Text2) };
        ((TextBlock)b.Child).HorizontalAlignment = HorizontalAlignment.Center;
        var host = Magnify(b, tip);
        host.MouseLeftButtonUp += click;
        return host;
    }

    /** 鼠标放上去放大一点（像 Mac 的 Dock） */
    FrameworkElement Magnify(FrameworkElement icon, string tip)
    {
        var scale = new ScaleTransform(1, 1);
        var host = new Border { Child = icon, Margin = new Thickness(4, 0, 4, 0), Background = Brushes.Transparent, Cursor = Cursors.Hand, ToolTip = tip, RenderTransform = scale, RenderTransformOrigin = new Point(0.5, 1), VerticalAlignment = VerticalAlignment.Bottom };
        void To(double v)
        {
            var a = new DoubleAnimation(v, TimeSpan.FromMilliseconds(120)) { EasingFunction = new QuadraticEase() };
            scale.BeginAnimation(ScaleTransform.ScaleXProperty, a);
            scale.BeginAnimation(ScaleTransform.ScaleYProperty, a);
        }
        host.MouseEnter += (_, _) => To(1.3);
        host.MouseLeave += (_, _) => To(1);
        return host;
    }

    /** 下载文件夹：点开是一叠最近的文件 */
    FrameworkElement DownloadsStack()
    {
        var img = Native.FileIcon(Downloads);
        var host = Magnify(img != null ? new Image { Source = img, Width = IconSize, Height = IconSize } : Tile(G.Download, "", (_, _) => { }), L("下载"));
        host.MouseLeftButtonUp += (_, e) =>
        {
            e.Handled = true;
            var p = m.Pal;
            var files = new DirectoryInfo(Downloads).EnumerateFileSystemInfos().Where(f => !f.Name.StartsWith(".") && !f.Name.EndsWith(".crdownload") && !f.Name.EndsWith(".tmp"))
                .OrderByDescending(f => f.LastWriteTimeUtc).Take(12).ToList();
            var wrap = new WrapPanel { Width = 360 };
            foreach (var f in files)
            {
                var path = f.FullName;
                var cell = UI.V(4, new Image { Source = Native.FileIcon(path), Width = 44, Height = 44 }, UI.T(f.Name, 11, p.Text));
                ((TextBlock)cell.Children[1]).TextAlignment = TextAlignment.Center;
                ((TextBlock)cell.Children[1]).MaxWidth = 82;
                cell.Width = 86; cell.Margin = new Thickness(2, 4, 2, 8); cell.Cursor = Cursors.Hand; cell.Background = Brushes.Transparent;
                cell.MouseLeftButtonUp += (_, _) => { stack!.IsOpen = false; Launch(path); };
                wrap.Children.Add(cell);
            }
            if (files.Count == 0) wrap.Children.Add(UI.T(L("下载文件夹是空的"), 12, p.Text3));
            var open = UI.Pill(L("在资源管理器中打开"), p, () => { stack!.IsOpen = false; Launch(Downloads); });
            open.HorizontalAlignment = HorizontalAlignment.Center;
            stack = new Popup
            {
                PlacementTarget = host, Placement = PlacementMode.Top, AllowsTransparency = true, StaysOpen = false, VerticalOffset = -8,
                Child = new Border { Background = p.Window, BorderBrush = p.CardBorder, BorderThickness = new Thickness(1), CornerRadius = new CornerRadius(16), Padding = new Thickness(12), Margin = new Thickness(12), Effect = UI.Shadow(24, 0.3),
                    Child = UI.V(8, UI.T(L("下载"), 13, p.Text2, FontWeights.SemiBold), wrap, open) },
            };
            stack.IsOpen = true;
        };
        return host;
    }

    static void Launch(string target, string? args = null)
    {
        try
        {
            var psi = new System.Diagnostics.ProcessStartInfo(target) { UseShellExecute = true };
            if (args != null) psi.Arguments = args;
            if (target == "shell:RecycleBinFolder") psi = new System.Diagnostics.ProcessStartInfo("explorer.exe", "shell:RecycleBinFolder") { UseShellExecute = true };
            System.Diagnostics.Process.Start(psi);
        }
        catch { }
    }

    void OnDrop(object s, DragEventArgs e)
    {
        if (e.Data.GetData(DataFormats.FileDrop) is not string[] paths) return;
        var apps = List("dockApps"); var files = List("dockFiles");
        foreach (var p in paths)
        {
            var ext = Path.GetExtension(p).ToLowerInvariant();
            if (ext is ".exe" or ".lnk" or ".url" or ".appref-ms") { if (!apps.Contains(p)) apps.Add(p); }
            else if (!files.Contains(p)) files.Add(p);
        }
        m.Store.SetWin("dockApps", U.Arr(apps));
        SaveList("dockFiles", files);
    }

    // —— 开始菜单里的程序（添加应用、第一次的默认 Dock 都从这里挑） ——
    public static List<string> StartMenuApps()
    {
        var dirs = new[]
        {
            Environment.GetFolderPath(Environment.SpecialFolder.CommonStartMenu),
            Environment.GetFolderPath(Environment.SpecialFolder.StartMenu),
        };
        var o = new List<string>();
        foreach (var d in dirs)
        {
            try { o.AddRange(Directory.EnumerateFiles(d, "*.lnk", SearchOption.AllDirectories)); } catch { }
        }
        return o.Where(p => !Path.GetFileName(p).Contains("uninstall", StringComparison.OrdinalIgnoreCase) && !Path.GetFileName(p).Contains("卸载"))
            .GroupBy(p => Path.GetFileNameWithoutExtension(p), StringComparer.OrdinalIgnoreCase).Select(g => g.First())
            .OrderBy(p => Path.GetFileNameWithoutExtension(p), StringComparer.CurrentCultureIgnoreCase).ToList();
    }

    static List<string> DefaultApps()
    {
        var all = StartMenuApps();
        var o = new List<string> { Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows), "explorer.exe") };
        foreach (var want in new[] { "Microsoft Edge", "Google Chrome", "Firefox", "微信", "WeChat", "QQ", "Visual Studio Code", "Spotify", "网易云音乐", "Notepad", "记事本" })
        {
            var hit = all.FirstOrDefault(p => Path.GetFileNameWithoutExtension(p).Equals(want, StringComparison.OrdinalIgnoreCase));
            if (hit != null) o.Add(hit);
            if (o.Count >= 6) break;
        }
        return o;
    }
}

/** 从开始菜单里挑一个程序放进 Dock */
public class AppPicker : Window
{
    public AppPicker(Model m, Action<string> add)
    {
        var p = m.Pal;
        Title = L("添加应用");
        Width = 420; Height = 560;
        WindowStartupLocation = WindowStartupLocation.CenterScreen;
        Background = p.Window;
        Topmost = true;
        var all = DockWindow.StartMenuApps();
        var search = new TextBox { FontSize = 14, Padding = new Thickness(10, 6, 10, 6), Foreground = p.Text, Background = p.Fill, BorderBrush = p.CardBorder, CaretBrush = p.Text, Margin = new Thickness(0, 0, 0, 10) };
        var list = new StackPanel();
        void Draw()
        {
            list.Children.Clear();
            var q = search.Text.Trim();
            foreach (var path in all.Where(x => q == "" || Path.GetFileNameWithoutExtension(x).Contains(q, StringComparison.OrdinalIgnoreCase)).Take(200))
            {
                var row = UI.H(10, new Image { Source = Native.FileIcon(path), Width = 28, Height = 28 }, UI.T(Path.GetFileNameWithoutExtension(path), 13.5, p.Text));
                row.Margin = new Thickness(0, 3, 0, 3); row.Background = Brushes.Transparent; row.Cursor = Cursors.Hand;
                row.MouseLeftButtonUp += (_, _) => { add(path); Close(); };
                list.Children.Add(row);
            }
        }
        search.TextChanged += (_, _) => Draw();
        Draw();
        var browse = UI.Pill(L("选其他程序…"), p, () =>
        {
            var dlg = new Microsoft.Win32.OpenFileDialog { Filter = L("程序") + "|*.exe;*.lnk|*.*|*.*" };
            if (dlg.ShowDialog() == true) { add(dlg.FileName); Close(); }
        });
        browse.HorizontalAlignment = HorizontalAlignment.Left;
        var root = new DockPanel { Margin = new Thickness(18) };
        DockPanel.SetDock(search, Dock.Top); root.Children.Add(search);
        DockPanel.SetDock(browse, Dock.Bottom); browse.Margin = new Thickness(0, 10, 0, 0); root.Children.Add(browse);
        root.Children.Add(new ScrollViewer { Content = list, VerticalScrollBarVisibility = ScrollBarVisibility.Auto });
        Content = root;
        Loaded += (_, _) => search.Focus();
    }
}
