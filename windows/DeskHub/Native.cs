// Windows 系统接口：把窗口放到桌面图标后面（WorkerW）、隐藏桌面图标、全局快捷键、取文件图标、壁纸、系统负载。
// 每个调用都包了 try，失败就退回普通做法，不会让程序崩掉。
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
using System.Windows;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Imaging;

namespace DeskHub;

public static class Native
{
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; public int W => Right - Left; public int H => Bottom - Top; }
    [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }

    public delegate bool EnumWindowsProc(IntPtr hwnd, IntPtr lParam);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc cb, IntPtr lParam);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern IntPtr FindWindow(string? cls, string? title);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern IntPtr FindWindowEx(IntPtr parent, IntPtr after, string? cls, string? title);
    [DllImport("user32.dll")] public static extern IntPtr SetParent(IntPtr child, IntPtr parent);
    [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr hwnd, IntPtr after, int x, int y, int cx, int cy, uint flags);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hwnd, int cmd);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hwnd);
    [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr hwnd);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hwnd, out RECT r);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hwnd);
    [DllImport("user32.dll")] public static extern bool GetCursorPos(out POINT p);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetClassName(IntPtr hwnd, StringBuilder sb, int max);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern uint RegisterWindowMessage(string name);
    [DllImport("user32.dll", SetLastError = true)] public static extern IntPtr SendMessageTimeout(IntPtr hwnd, uint msg, IntPtr w, IntPtr l, uint flags, uint timeout, out IntPtr result);
    [DllImport("user32.dll", EntryPoint = "GetWindowLongPtrW")] public static extern IntPtr GetWindowLongPtr(IntPtr hwnd, int idx);
    [DllImport("user32.dll", EntryPoint = "SetWindowLongPtrW")] public static extern IntPtr SetWindowLongPtr(IntPtr hwnd, int idx, IntPtr v);
    [DllImport("user32.dll")] public static extern bool RegisterHotKey(IntPtr hwnd, int id, uint mods, uint vk);
    [DllImport("user32.dll")] public static extern bool UnregisterHotKey(IntPtr hwnd, int id);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern bool SystemParametersInfo(uint action, uint param, StringBuilder sb, uint winIni);
    [DllImport("user32.dll")] static extern uint GetSysColor(int idx);
    [DllImport("user32.dll")] static extern IntPtr MonitorFromWindow(IntPtr hwnd, uint flags);
    [DllImport("user32.dll")] static extern bool GetMonitorInfo(IntPtr mon, ref MONITORINFO mi);
    [StructLayout(LayoutKind.Sequential)] struct MONITORINFO { public int cbSize; public RECT rcMonitor, rcWork; public uint dwFlags; }

    [StructLayout(LayoutKind.Sequential)] public struct APPBARDATA { public int cbSize; public IntPtr hWnd; public uint uCallbackMessage; public uint uEdge; public RECT rc; public IntPtr lParam; }
    [DllImport("shell32.dll")] public static extern UIntPtr SHAppBarMessage(uint msg, ref APPBARDATA data);

    public const int GWL_EXSTYLE = -20;
    public const long WS_EX_TOOLWINDOW = 0x80, WS_EX_NOACTIVATE = 0x08000000, WS_EX_TRANSPARENT = 0x20, WS_EX_APPWINDOW = 0x40000;
    public const uint SWP_NOSIZE = 0x1, SWP_NOMOVE = 0x2, SWP_NOZORDER = 0x4, SWP_NOACTIVATE = 0x10, SWP_SHOWWINDOW = 0x40;
    public static readonly IntPtr HWND_BOTTOM = new(1), HWND_TOPMOST = new(-1);

    public static IntPtr Hwnd(Window w) => new WindowInteropHelper(w).EnsureHandle();

    public static void AddExStyle(IntPtr hwnd, long bits) =>
        SetWindowLongPtr(hwnd, GWL_EXSTYLE, new IntPtr(GetWindowLongPtr(hwnd, GWL_EXSTYLE).ToInt64() | bits));
    public static void RemoveExStyle(IntPtr hwnd, long bits) =>
        SetWindowLongPtr(hwnd, GWL_EXSTYLE, new IntPtr(GetWindowLongPtr(hwnd, GWL_EXSTYLE).ToInt64() & ~bits));

    // —— 桌面层 ——

    /** 桌面图标那一层（SHELLDLL_DefView）和它后面的壁纸层（WorkerW）。Win10、Win11（含 24H2 的新结构）都认 */
    public record DesktopHost(IntPtr Parent, IntPtr InsertAfter);

    public static DesktopHost? FindDesktopHost()
    {
        try
        {
            var progman = FindWindow("Progman", null);
            if (progman == IntPtr.Zero) return null;
            // 让 Explorer 把壁纸层单独分出一个 WorkerW 窗口
            SendMessageTimeout(progman, 0x052C, IntPtr.Zero, IntPtr.Zero, 0, 1000, out _);
            SendMessageTimeout(progman, 0x052C, new IntPtr(0xD), new IntPtr(1), 0, 1000, out _);
            IntPtr worker = IntPtr.Zero;
            EnumWindows((top, _) =>
            {
                if (FindWindowEx(top, IntPtr.Zero, "SHELLDLL_DefView", null) != IntPtr.Zero)
                    worker = FindWindowEx(IntPtr.Zero, top, "WorkerW", null);
                return true;
            }, IntPtr.Zero);
            if (worker != IntPtr.Zero) return new DesktopHost(worker, IntPtr.Zero);
            // Win11 24H2 起：WorkerW 和图标层都挂在 Progman 下面，要插在两者之间
            var defView = FindWindowEx(progman, IntPtr.Zero, "SHELLDLL_DefView", null);
            var inner = FindWindowEx(progman, IntPtr.Zero, "WorkerW", null);
            if (defView != IntPtr.Zero && inner != IntPtr.Zero) return new DesktopHost(progman, defView);
        }
        catch { }
        return null;
    }

    /** 把窗口放进桌面层，铺满 screen（物理像素） */
    public static bool Embed(IntPtr hwnd, DesktopHost host, RECT screen)
    {
        try
        {
            SetParent(hwnd, host.Parent);
            GetWindowRect(host.Parent, out var pr);
            var after = host.InsertAfter != IntPtr.Zero ? host.InsertAfter : IntPtr.Zero;
            SetWindowPos(hwnd, after, screen.Left - pr.Left, screen.Top - pr.Top, screen.W, screen.H, SWP_NOACTIVATE | SWP_SHOWWINDOW | (after == IntPtr.Zero ? SWP_NOZORDER : 0));
            return true;
        }
        catch { return false; }
    }

    /** 桌面图标列表（隐藏它 = 清空桌面；退出时会还原） */
    static IntPtr IconList()
    {
        IntPtr list = IntPtr.Zero;
        EnumWindows((top, _) =>
        {
            var dv = FindWindowEx(top, IntPtr.Zero, "SHELLDLL_DefView", null);
            if (dv != IntPtr.Zero) list = FindWindowEx(dv, IntPtr.Zero, "SysListView32", null);
            return list == IntPtr.Zero;
        }, IntPtr.Zero);
        if (list == IntPtr.Zero)
        {
            var progman = FindWindow("Progman", null);
            var dv = FindWindowEx(progman, IntPtr.Zero, "SHELLDLL_DefView", null);
            if (dv != IntPtr.Zero) list = FindWindowEx(dv, IntPtr.Zero, "SysListView32", null);
        }
        return list;
    }

    public static void SetDesktopIconsVisible(bool show)
    {
        try { var l = IconList(); if (l != IntPtr.Zero) ShowWindow(l, show ? 5 : 0); } catch { }
    }

    /** 前台是不是一个全屏的程序（看视频、打游戏时 Dock 自动让开） */
    public static bool ForegroundIsFullscreen(IEnumerable<IntPtr> ours)
    {
        try
        {
            var fg = GetForegroundWindow();
            if (fg == IntPtr.Zero) return false;
            foreach (var o in ours) if (o == fg) return false;
            var sb = new StringBuilder(64);
            GetClassName(fg, sb, 64);
            var cls = sb.ToString();
            if (cls is "Progman" or "WorkerW" or "Shell_TrayWnd" or "Shell_SecondaryTrayWnd") return false;
            GetWindowRect(fg, out var r);
            var mi = new MONITORINFO { cbSize = Marshal.SizeOf<MONITORINFO>() };
            if (!GetMonitorInfo(MonitorFromWindow(fg, 2), ref mi)) return false;
            return r.Left <= mi.rcMonitor.Left && r.Top <= mi.rcMonitor.Top && r.Right >= mi.rcMonitor.Right && r.Bottom >= mi.rcMonitor.Bottom;
        }
        catch { return false; }
    }

    // —— 壁纸（每块屏幕可能不一样：用系统的 IDesktopWallpaper，拿不到就用全局那张） ——
    [ComImport, Guid("B92B56A9-8B55-4E14-9A89-0199BBB6F93B"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IDesktopWallpaper
    {
        void SetWallpaper([MarshalAs(UnmanagedType.LPWStr)] string? monitorID, [MarshalAs(UnmanagedType.LPWStr)] string wallpaper);
        [return: MarshalAs(UnmanagedType.LPWStr)] string GetWallpaper([MarshalAs(UnmanagedType.LPWStr)] string? monitorID);
        [return: MarshalAs(UnmanagedType.LPWStr)] string GetMonitorDevicePathAt(uint index);
        uint GetMonitorDevicePathCount();
        RECT GetMonitorRECT([MarshalAs(UnmanagedType.LPWStr)] string monitorID);
        void SetBackgroundColor(uint color);
        uint GetBackgroundColor();
        void SetPosition(int position);
        int GetPosition();
    }
    [ComImport, Guid("C2CF3110-460E-4fc1-B9D0-8A1C0C9CC4BD")] class DesktopWallpaperClass { }

    public record Wallpaper(string Path, Stretch Stretch, Color Background);

    public static Wallpaper GetWallpaper(RECT screen)
    {
        var bg = SysDesktopColor();
        try
        {
            var dw = (IDesktopWallpaper)new DesktopWallpaperClass();
            var stretch = dw.GetPosition() switch { 0 => Stretch.None, 2 => Stretch.Fill, 3 => Stretch.Uniform, _ => Stretch.UniformToFill };
            try { var c = dw.GetBackgroundColor(); bg = Color.FromRgb((byte)(c & 0xFF), (byte)((c >> 8) & 0xFF), (byte)((c >> 16) & 0xFF)); } catch { }
            uint n = dw.GetMonitorDevicePathCount();
            for (uint i = 0; i < n; i++)
            {
                var id = dw.GetMonitorDevicePathAt(i);
                var r = dw.GetMonitorRECT(id);
                if (r.Left == screen.Left && r.Top == screen.Top)
                {
                    var p = dw.GetWallpaper(id);
                    if (!string.IsNullOrEmpty(p) && System.IO.File.Exists(p)) return new Wallpaper(p, stretch, bg);
                }
            }
            var all = dw.GetWallpaper(null);
            if (!string.IsNullOrEmpty(all) && System.IO.File.Exists(all)) return new Wallpaper(all, stretch, bg);
        }
        catch { }
        try
        {
            var sb = new StringBuilder(520);
            SystemParametersInfo(0x73, 520, sb, 0);   // SPI_GETDESKWALLPAPER
            var p = sb.ToString();
            if (System.IO.File.Exists(p)) return new Wallpaper(p, Stretch.UniformToFill, bg);
        }
        catch { }
        return new Wallpaper("", Stretch.UniformToFill, bg);
    }

    static Color SysDesktopColor()
    {
        try { var c = GetSysColor(1); return Color.FromRgb((byte)(c & 0xFF), (byte)((c >> 8) & 0xFF), (byte)((c >> 16) & 0xFF)); }
        catch { return Color.FromRgb(20, 20, 24); }
    }

    // —— 文件和程序的图标（48 像素，带透明） ——
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct SHFILEINFO { public IntPtr hIcon; public int iIcon; public uint attr; [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 260)] public string name; [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 80)] public string type; }
    [DllImport("shell32.dll", CharSet = CharSet.Unicode)] static extern IntPtr SHGetFileInfo(string path, uint attr, ref SHFILEINFO fi, uint size, uint flags);
    [DllImport("shell32.dll")] static extern int SHGetImageList(int iImageList, ref Guid riid, out IImageList ppv);
    [DllImport("user32.dll")] static extern bool DestroyIcon(IntPtr h);

    [ComImport, Guid("46EB5926-582E-4017-9FDF-E8998DAA0950"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IImageList
    {
        [PreserveSig] int Add(IntPtr hbmImage, IntPtr hbmMask, ref int pi);
        [PreserveSig] int ReplaceIcon(int i, IntPtr hicon, ref int pi);
        [PreserveSig] int SetOverlayImage(int iImage, int iOverlay);
        [PreserveSig] int Replace(int i, IntPtr hbmImage, IntPtr hbmMask);
        [PreserveSig] int AddMasked(IntPtr hbmImage, int crMask, ref int pi);
        [PreserveSig] int Draw(IntPtr pimldp);
        [PreserveSig] int Remove(int i);
        [PreserveSig] int GetIcon(int i, int flags, ref IntPtr picon);
    }

    static readonly Dictionary<string, ImageSource?> iconCache = new(StringComparer.OrdinalIgnoreCase);

    public static ImageSource? FileIcon(string path)
    {
        if (iconCache.TryGetValue(path, out var hit)) return hit;
        ImageSource? img = null;
        try
        {
            var fi = new SHFILEINFO();
            const uint SHGFI_SYSICONINDEX = 0x4000, SHGFI_ICON = 0x100, SHGFI_LARGEICON = 0x0;
            SHGetFileInfo(path, 0, ref fi, (uint)Marshal.SizeOf<SHFILEINFO>(), SHGFI_SYSICONINDEX);
            var iid = new Guid("46EB5926-582E-4017-9FDF-E8998DAA0950");
            if (SHGetImageList(0x2 /* SHIL_EXTRALARGE 48px */, ref iid, out var list) == 0)
            {
                IntPtr h = IntPtr.Zero;
                list.GetIcon(fi.iIcon, 0x1 /* ILD_TRANSPARENT */, ref h);
                if (h != IntPtr.Zero) { img = Imaging.CreateBitmapSourceFromHIcon(h, Int32Rect.Empty, BitmapSizeOptions.FromEmptyOptions()); DestroyIcon(h); }
            }
            if (img == null)
            {
                SHGetFileInfo(path, 0, ref fi, (uint)Marshal.SizeOf<SHFILEINFO>(), SHGFI_ICON | SHGFI_LARGEICON);
                if (fi.hIcon != IntPtr.Zero) { img = Imaging.CreateBitmapSourceFromHIcon(fi.hIcon, Int32Rect.Empty, BitmapSizeOptions.FromEmptyOptions()); DestroyIcon(fi.hIcon); }
            }
            img?.Freeze();
        }
        catch { }
        iconCache[path] = img;
        return img;
    }

    // —— 系统负载 ——
    [DllImport("kernel32.dll")] public static extern bool GetSystemTimes(out long idle, out long kernel, out long user);
    [StructLayout(LayoutKind.Sequential)]
    public struct MEMORYSTATUSEX { public uint dwLength, dwMemoryLoad; public ulong ullTotalPhys, ullAvailPhys, ullTotalPageFile, ullAvailPageFile, ullTotalVirtual, ullAvailVirtual, ullAvailExtendedVirtual; }
    [DllImport("kernel32.dll")] public static extern bool GlobalMemoryStatusEx(ref MEMORYSTATUSEX m);

    // —— 繁体 → 简体（系统自带） ——
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
    static extern int LCMapStringEx(string locale, uint flags, string src, int srcLen, StringBuilder? dest, int destLen, IntPtr a, IntPtr b, IntPtr c);
    public static string T2S(string s)
    {
        try
        {
            const uint LCMAP_SIMPLIFIED_CHINESE = 0x02000000;
            int n = LCMapStringEx("zh-CN", LCMAP_SIMPLIFIED_CHINESE, s, s.Length, null, 0, IntPtr.Zero, IntPtr.Zero, IntPtr.Zero);
            if (n <= 0) return s;
            var sb = new StringBuilder(n);
            LCMapStringEx("zh-CN", LCMAP_SIMPLIFIED_CHINESE, s, s.Length, sb, n, IntPtr.Zero, IntPtr.Zero, IntPtr.Zero);
            return sb.ToString();
        }
        catch { return s; }
    }
}
