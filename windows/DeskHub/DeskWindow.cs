// 桌面层：每块屏幕一个窗口，放在桌面图标后面（和壁纸同一层），画上壁纸和组件。
// 鼠标点不到它（图标在它上面）；要点组件，按 Ctrl+Alt+空格 打开浮层。
// 万一放不进桌面层（Explorer 结构变了），就退成「最底层的透明窗口」，只画组件、不挡鼠标。
using System;
using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;

namespace DeskHub;

public class DeskWindow : Window
{
    readonly Model m;
    public readonly string Key;
    public readonly System.Windows.Forms.Screen Screen;
    readonly Native.DesktopHost? host;
    readonly Border wall = new();
    readonly GridView grid;
    readonly Border gridHost;
    string wallKey = "";
    readonly DispatcherTimer wallTimer = new() { Interval = TimeSpan.FromMinutes(2) };

    public bool Embedded => host != null;

    public DeskWindow(Model m, System.Windows.Forms.Screen screen, string key, Native.DesktopHost? host)
    {
        this.m = m; Screen = screen; Key = key; this.host = host;
        WindowStyle = WindowStyle.None;
        ResizeMode = ResizeMode.NoResize;
        ShowInTaskbar = false;
        ShowActivated = false;
        Focusable = false;
        Title = "Glancedesk Desktop";
        if (host == null) { AllowsTransparency = true; Background = Brushes.Transparent; }
        else Background = Brushes.Black;

        grid = new GridView(m, key, false);
        var root = new Grid();
        if (host != null) root.Children.Add(wall);
        gridHost = new Border { Child = grid };
        root.Children.Add(gridHost);
        Loaded += (_, _) => Relayout();
        Content = root;

        var hwnd = Native.Hwnd(this);
        Native.AddExStyle(hwnd, Native.WS_EX_TOOLWINDOW | Native.WS_EX_NOACTIVATE);
        var b = screen.Bounds;
        var rect = new Native.RECT { Left = b.Left, Top = b.Top, Right = b.Right, Bottom = b.Bottom };
        if (host != null)
        {
            Native.Embed(hwnd, host, rect);
            LoadWallpaper();
            wallTimer.Tick += (_, _) => LoadWallpaper();
            wallTimer.Start();
            Microsoft.Win32.SystemEvents.UserPreferenceChanged += OnPrefChanged;
        }
        else
        {
            Native.AddExStyle(hwnd, Native.WS_EX_TRANSPARENT);
            Native.SetWindowPos(hwnd, Native.HWND_BOTTOM, b.Left, b.Top, b.Width, b.Height, Native.SWP_NOACTIVATE);
        }
        Show();
        if (host != null) Native.Embed(hwnd, host, rect);   // WPF 显示时可能动过位置，再摆一次
        else Native.SetWindowPos(hwnd, Native.HWND_BOTTOM, b.Left, b.Top, b.Width, b.Height, Native.SWP_NOACTIVATE);
        Closed += (_, _) => { wallTimer.Stop(); Microsoft.Win32.SystemEvents.UserPreferenceChanged -= OnPrefChanged; };
    }

    public void Relayout() => gridHost.Margin = new Thickness(0, 0, 0, App.BottomGap(this, Screen));

    void OnPrefChanged(object? s, Microsoft.Win32.UserPreferenceChangedEventArgs e) => Dispatcher.BeginInvoke(LoadWallpaper);

    /** 自己画壁纸（我们盖在壁纸那一层上面，所以要把壁纸照着画出来） */
    void LoadWallpaper()
    {
        var b = Screen.Bounds;
        var w = Native.GetWallpaper(new Native.RECT { Left = b.Left, Top = b.Top, Right = b.Right, Bottom = b.Bottom });
        var stamp = w.Path == "" ? "" : w.Path + "|" + File.GetLastWriteTimeUtc(w.Path).Ticks;
        if (stamp == wallKey && wall.Background != null) return;
        wallKey = stamp;
        wall.Background = new SolidColorBrush(w.Background);
        if (w.Path == "") return;
        try
        {
            var bmp = new BitmapImage();
            bmp.BeginInit();
            bmp.UriSource = new Uri(w.Path);
            bmp.CacheOption = BitmapCacheOption.OnLoad;   // 读完就放开文件，不锁住壁纸
            bmp.CreateOptions = BitmapCreateOptions.IgnoreImageCache;
            bmp.DecodePixelWidth = Math.Min(3840, b.Width);
            bmp.EndInit();
            bmp.Freeze();
            var inner = new Border { Background = new ImageBrush(bmp) { Stretch = w.Stretch } };
            wall.Child = inner;
        }
        catch { }
    }
}
