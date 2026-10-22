// 组件网格：桌面层和浮层共用。8 列 × 4 行，按格子大小摆卡片；编辑时能拖动、换档、删掉、打开设置。
using System;
using System.Collections.Generic;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using DeskHub.Core;
using static DeskHub.Core.I18n;

namespace DeskHub;

public class GridView : Canvas
{
    readonly Model m;
    public readonly string ScreenKey;
    public readonly bool Interactive;
    bool editing;
    readonly Dictionary<string, Card> cards = new();
    public Action<string>? OpenConfig;

    public GridView(Model m, string screenKey, bool interactive)
    {
        this.m = m; ScreenKey = screenKey; Interactive = interactive;
        ClipToBounds = false;
        SizeChanged += (_, _) => Rebuild();
        m.Changed += OnChanged;
        Unloaded += (_, _) => m.Changed -= OnChanged;
    }

    public bool Editing { get => editing; set { editing = value; Rebuild(); } }

    void OnChanged(HashSet<string> keys)
    {
        if (keys.Contains("layout") || keys.Contains("theme") || keys.Contains("lang")) { Rebuild(); return; }
        foreach (var c in cards.Values)
            if (Widgets.Deps.TryGetValue(c.Item.Type, out var deps) && deps.Any(keys.Contains)) c.Refresh();
    }

    public void Rebuild()
    {
        if (ActualWidth < 50) return;
        Children.Clear();
        cards.Clear();
        foreach (var it in Layouts.Visible(m.LayoutFor(ScreenKey)))
        {
            var r = Layouts.ToRect(it.Col, it.Row, it.W, it.H, ActualWidth, ActualHeight);
            var card = new Card(m, it, r, Interactive, editing, this);
            SetLeft(card, r.Left); SetTop(card, r.Top);
            Children.Add(card);
            cards[it.Id] = card;
        }
    }

    // —— 编辑：拖动松手吸到最近的格 ——
    internal void DropCard(Card c, double left, double top)
    {
        var (col, row) = Layouts.FromPoint(left, top, ActualWidth, ActualHeight);
        m.SetLayout(ScreenKey, Layouts.Move(m.LayoutFor(ScreenKey), c.Item.Id, col, row));
    }

    internal void Resize(Card c, string size) => m.SetLayout(ScreenKey, Layouts.SetSize(m.LayoutFor(ScreenKey), c.Item.Id, size));
    internal void Remove(Card c) => m.SetLayout(ScreenKey, Layouts.RemoveInstance(m.LayoutFor(ScreenKey), c.Item.Id));

    public void Add(string type)
    {
        var l = m.LayoutFor(ScreenKey);
        var cur = Layouts.Normalize(l).Item(type);
        string? id = type;
        Layout next;
        if (cur != null && !cur.On) next = Layouts.Toggle(l, type, true);
        else { (next, id) = Layouts.AddInstance(l, type); }
        m.SetLayout(ScreenKey, next);
        if (id != null && type is "rss" or "github" or "countdown" && m.Store.Config(id).Count == 0) OpenConfig?.Invoke(id);
    }

    /** 「添加组件」菜单 */
    public ContextMenu AddMenu()
    {
        var menu = new ContextMenu();
        var l = Layouts.Normalize(m.LayoutFor(ScreenKey));
        foreach (var d in Layouts.Widgets.Where(w => !Layouts.Hidden.Contains(w.Id)))
        {
            var cur = l.Item(d.Id);
            if (cur?.On != true) { var mi = new MenuItem { Header = d.Name }; mi.Click += (_, _) => Add(d.Id); menu.Items.Add(mi); }
            else if (d.Multi) { var mi = new MenuItem { Header = L("再加一个「%@」", d.Name) }; mi.Click += (_, _) => Add(d.Id); menu.Items.Add(mi); }
        }
        return menu;
    }
}

/** 一张卡片 */
class Card : Border
{
    readonly Model m;
    public readonly LayoutItem Item;
    readonly CellRect r;
    readonly bool interactive, editing;
    readonly GridView grid;
    readonly ContentControl body = new();
    Point dragStart; Point origin; bool dragging;

    public Card(Model m, LayoutItem it, CellRect r, bool interactive, bool editing, GridView grid)
    {
        this.m = m; Item = it; this.r = r; this.interactive = interactive; this.editing = editing; this.grid = grid;
        Width = r.Width; Height = r.Height;
        CornerRadius = new CornerRadius(20);
        Background = m.Pal.Card;
        BorderBrush = editing ? m.Pal.AccentB : m.Pal.CardBorder;
        BorderThickness = new Thickness(editing ? 1.5 : 1);
        Padding = new Thickness(16, 14, 16, 14);
        ClipToBounds = true;
        var root = new Grid();
        root.Children.Add(body);
        if (editing) root.Children.Add(EditChrome());
        Child = root;
        Refresh();
        if (editing)
        {
            Cursor = Cursors.SizeAll;
            MouseLeftButtonDown += StartDrag;
            MouseMove += DragMove;
            MouseLeftButtonUp += EndDrag;
        }
    }

    public void Refresh()
    {
        // 正在打字（便签、待办输入框）时不重画，免得把光标弄丢
        if (IsKeyboardFocusWithin) return;
        body.Content = Widgets.Build(new Ctx(m, Item, r.Width - 32, r.Height - 28, interactive && !editing));
    }

    UIElement EditChrome()
    {
        var p = m.Pal;
        var top = UI.H(2,
            Widgets.Configurable.Contains(Item.Type) ? UI.IconButton(G.Settings, p, () => grid.OpenConfig?.Invoke(Item.Id), 13, L("设置")) : null,
            UI.IconButton(G.Close, p, () => grid.Remove(this), 13, L("删掉这个组件")));
        // 底下垫一块，免得压住卡片右上角的字
        var topBox = new Border { Child = top, Background = p.Window, CornerRadius = new CornerRadius(10), Padding = new Thickness(2, 0, 2, 0),
            HorizontalAlignment = HorizontalAlignment.Right, VerticalAlignment = VerticalAlignment.Top, Margin = new Thickness(0, -8, -8, 0) };
        var sizes = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Left, VerticalAlignment = VerticalAlignment.Bottom, Margin = new Thickness(-4, 0, 0, -4) };
        var def = Layouts.Def(Item.Type);
        if (def != null && def.Sizes.Length > 1)
            foreach (var s in def.Sizes)
            {
                var on = s == Item.Size;
                var chip = new Border { Background = on ? p.AccentB : p.Fill2, CornerRadius = new CornerRadius(8), Padding = new Thickness(8, 2, 8, 3), Margin = new Thickness(0, 0, 4, 0), Cursor = Cursors.Hand,
                    Child = new TextBlock { Text = Layouts.SizeLabel(s), FontSize = 11, Foreground = on ? Brushes.White : p.Text } };
                var size = s;
                chip.MouseLeftButtonDown += (_, e) => { e.Handled = true; grid.Resize(this, size); };
                sizes.Children.Add(chip);
            }
        var g = new Grid { Background = new SolidColorBrush(Color.FromArgb(1, 0, 0, 0)) };   // 整张卡都能抓
        g.Children.Add(topBox); g.Children.Add(sizes);
        return g;
    }

    void StartDrag(object s, MouseButtonEventArgs e)
    {
        dragStart = e.GetPosition(grid);
        origin = new Point(Canvas.GetLeft(this), Canvas.GetTop(this));
        dragging = true;
        CaptureMouse();
        Panel.SetZIndex(this, 99);
        Opacity = 0.85;
    }

    void DragMove(object s, MouseEventArgs e)
    {
        if (!dragging) return;
        var p = e.GetPosition(grid);
        Canvas.SetLeft(this, origin.X + p.X - dragStart.X);
        Canvas.SetTop(this, origin.Y + p.Y - dragStart.Y);
    }

    void EndDrag(object s, MouseButtonEventArgs e)
    {
        if (!dragging) return;
        dragging = false;
        ReleaseMouseCapture();
        Opacity = 1;
        var moved = Math.Abs(Canvas.GetLeft(this) - origin.X) + Math.Abs(Canvas.GetTop(this) - origin.Y) > 6;
        if (moved) grid.DropCard(this, Canvas.GetLeft(this), Canvas.GetTop(this));
        else { Canvas.SetLeft(this, origin.X); Canvas.SetTop(this, origin.Y); }
    }
}
