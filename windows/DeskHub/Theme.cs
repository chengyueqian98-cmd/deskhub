// 外观：浅色 / 深色（默认跟系统），强调色；还有一套写界面用的小工具（代码里直接拼界面，不用 XAML）。
using System;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Effects;
using Microsoft.Win32;

namespace DeskHub;

public class Palette
{
    public bool Dark;
    public Color Accent;
    public Brush Text = null!, Text2 = null!, Text3 = null!, Card = null!, CardBorder = null!, Fill = null!, Fill2 = null!, Window = null!, Dim = null!, AccentB = null!, Up = null!, Down = null!, Orange = null!;

    public static readonly (string id, string zh, Color c)[] Accents =
    {
        ("blue", "蓝", Color.FromRgb(0, 122, 255)), ("purple", "紫", Color.FromRgb(175, 82, 222)), ("pink", "粉", Color.FromRgb(255, 45, 85)),
        ("orange", "橙", Color.FromRgb(255, 149, 0)), ("green", "绿", Color.FromRgb(52, 199, 89)), ("graphite", "石墨", Color.FromRgb(142, 142, 147)),
    };

    public static bool SystemDark()
    {
        try { return Registry.GetValue(@"HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize", "AppsUseLightTheme", 1) is int v && v == 0; }
        catch { return false; }
    }

    public static Palette Make(string theme, string accent, string colors)
    {
        var dark = theme == "dark" || (theme == "auto" && SystemDark());
        var a = Array.Find(Accents, x => x.id == accent).c;
        if (a == default) a = Accents[0].c;
        static SolidColorBrush B(byte r, byte g, byte b, byte alpha = 255) { var x = new SolidColorBrush(Color.FromArgb(alpha, r, g, b)); x.Freeze(); return x; }
        var p = new Palette { Dark = dark, Accent = a };
        p.AccentB = new SolidColorBrush(a); p.AccentB.Freeze();
        if (dark)
        {
            p.Text = B(245, 245, 247); p.Text2 = B(235, 235, 245, 160); p.Text3 = B(235, 235, 245, 100);
            p.Card = B(28, 28, 30, 196); p.CardBorder = B(255, 255, 255, 22); p.Fill = B(255, 255, 255, 18); p.Fill2 = B(255, 255, 255, 34);
            p.Window = B(28, 28, 30); p.Dim = B(0, 0, 0, 150);
        }
        else
        {
            p.Text = B(29, 29, 31); p.Text2 = B(60, 60, 67, 160); p.Text3 = B(60, 60, 67, 110);
            p.Card = B(255, 255, 255, 210); p.CardBorder = B(0, 0, 0, 14); p.Fill = B(0, 0, 0, 10); p.Fill2 = B(0, 0, 0, 22);
            p.Window = B(246, 246, 248); p.Dim = B(242, 242, 247, 170);
        }
        p.Orange = B(255, 149, 0);
        var red = B(255, 69, 58); var green = B(48, 209, 88);
        (p.Up, p.Down) = colors switch { "rup" => (red, green), "gup" => (green, red), _ => (p.Text, p.Text2) };
        return p;
    }
}

/** 拼界面的小工具 */
static class UI
{
    public static readonly FontFamily Font = new("Segoe UI Variable Text, Segoe UI, Microsoft YaHei UI");
    public static readonly FontFamily Display = new("Segoe UI Variable Display, Segoe UI, Microsoft YaHei UI");
    public static readonly FontFamily Num = new("Segoe UI Variable Display, Segoe UI");
    public static readonly FontFamily Icons = new("Segoe Fluent Icons, Segoe MDL2 Assets");

    public static TextBlock T(string text, double size, Brush brush, FontWeight? weight = null, FontFamily? font = null) => new()
    {
        Text = text, FontSize = size, Foreground = brush, FontWeight = weight ?? FontWeights.Normal, FontFamily = font ?? Font,
        TextTrimming = TextTrimming.CharacterEllipsis, TextWrapping = TextWrapping.NoWrap,
    };

    public static TextBlock Wrap(string text, double size, Brush brush, int maxLines = 0)
    {
        var t = T(text, size, brush);
        t.TextWrapping = TextWrapping.Wrap;
        if (maxLines > 0) t.MaxHeight = size * 1.45 * maxLines;
        return t;
    }

    public static TextBlock Icon(string glyph, double size, Brush brush) => new() { Text = glyph, FontFamily = Icons, FontSize = size, Foreground = brush, VerticalAlignment = VerticalAlignment.Center };

    public static StackPanel V(double gap, params UIElement?[] kids)
    {
        var s = new StackPanel { Orientation = Orientation.Vertical };
        bool first = true;
        foreach (var k in kids) { if (k == null) continue; if (!first && k is FrameworkElement f) f.Margin = new Thickness(f.Margin.Left, f.Margin.Top + gap, f.Margin.Right, f.Margin.Bottom); s.Children.Add(k); first = false; }
        return s;
    }

    public static StackPanel H(double gap, params UIElement?[] kids)
    {
        var s = new StackPanel { Orientation = Orientation.Horizontal };
        bool first = true;
        foreach (var k in kids) { if (k == null) continue; if (!first && k is FrameworkElement f) f.Margin = new Thickness(f.Margin.Left + gap, f.Margin.Top, f.Margin.Right, f.Margin.Bottom); s.Children.Add(k); first = false; }
        return s;
    }

    /** 左边一个、右边一个（中间撑开） */
    public static DockPanel Row(UIElement left, UIElement? right, double height = double.NaN)
    {
        var d = new DockPanel { LastChildFill = true, Height = height };
        if (right != null) { DockPanel.SetDock(right, Dock.Right); if (right is FrameworkElement rf) rf.VerticalAlignment = VerticalAlignment.Center; d.Children.Add(right); }
        if (left is FrameworkElement lf) lf.VerticalAlignment = VerticalAlignment.Center;
        d.Children.Add(left);
        return d;
    }

    public static Border Box(UIElement child, Brush bg, double radius, Thickness pad) => new() { Child = child, Background = bg, CornerRadius = new CornerRadius(radius), Padding = pad };

    public static Border Bar(double pct, double width, Brush fg, Brush bg, double h = 5)
    {
        var inner = new Border { Background = fg, CornerRadius = new CornerRadius(h / 2), Width = Math.Max(h, width * Math.Clamp(pct, 0, 1)), HorizontalAlignment = HorizontalAlignment.Left };
        return new Border { Background = bg, CornerRadius = new CornerRadius(h / 2), Height = h, Width = width, Child = inner };
    }

    /** 圆角药丸按钮 */
    public static Button Pill(string text, Palette p, Action click, bool primary = false, double size = 12.5)
    {
        var b = new Button
        {
            Content = new TextBlock { Text = text, FontSize = size, FontFamily = Font, Foreground = primary ? Brushes.White : p.Text, FontWeight = primary ? FontWeights.SemiBold : FontWeights.Normal },
            Cursor = System.Windows.Input.Cursors.Hand, Focusable = false,
        };
        b.Template = PillTemplate(primary ? p.AccentB : p.Fill2);
        b.Click += (_, _) => click();
        return b;
    }

    static ControlTemplate PillTemplate(Brush bg)
    {
        var t = new ControlTemplate(typeof(Button));
        var bd = new FrameworkElementFactory(typeof(Border));
        bd.SetValue(Border.BackgroundProperty, bg);
        bd.SetValue(Border.CornerRadiusProperty, new CornerRadius(99));
        bd.SetValue(Border.PaddingProperty, new Thickness(14, 5, 14, 6));
        var cp = new FrameworkElementFactory(typeof(ContentPresenter));
        cp.SetValue(ContentPresenter.HorizontalAlignmentProperty, HorizontalAlignment.Center);
        cp.SetValue(ContentPresenter.VerticalAlignmentProperty, VerticalAlignment.Center);
        bd.AppendChild(cp);
        t.VisualTree = bd;
        return t;
    }

    /** 只有图标的小按钮 */
    public static Button IconButton(string glyph, Palette p, Action click, double size = 13, string tip = "")
    {
        var b = new Button { Content = Icon(glyph, size, p.Text), Cursor = System.Windows.Input.Cursors.Hand, Focusable = false, ToolTip = tip == "" ? null : tip };
        var t = new ControlTemplate(typeof(Button));
        var bd = new FrameworkElementFactory(typeof(Border));
        bd.SetValue(Border.BackgroundProperty, Brushes.Transparent);
        bd.SetValue(Border.PaddingProperty, new Thickness(4));
        bd.AppendChild(new FrameworkElementFactory(typeof(ContentPresenter)));
        t.VisualTree = bd;
        b.Template = t;
        b.Click += (_, _) => click();
        return b;
    }

    public static DropShadowEffect Shadow(double blur = 24, double opacity = 0.25) => new() { BlurRadius = blur, ShadowDepth = 4, Direction = 270, Opacity = opacity, Color = Colors.Black };

    public static void Open(string url)
    {
        try { System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo(url) { UseShellExecute = true }); } catch { }
    }
}

/** 常用图标（Segoe Fluent Icons / MDL2 的字形） */
static class G
{
    public const string Add = "", Close = "", Settings = "", Mail = "", Calendar = "", Clock = "", Globe = "",
        Music = "", Play = "", Pause = "", Prev = "", Next = "", Check = "", Delete = "", Folder = "",
        Down = "", Up = "", Search = "", Refresh = "", Star = "", Doc = "", Edit = "", More = "",
        News = "", Chart = "", Note = "", Photo = "", Timer = "", Heart = "", Gift = "", Pin = "",
        Download = "", Recycle = "", Apps = "", Cpu = "", Money = "", Moon = "", Umbrella = "", Person = "";
}
