// 多语言：界面文字直接写中文，L("中文") 在英文模式下查对照表；查不到就显示中文原文。
// 格式和 Mac 版一样用 %@ 占位、%% 表示百分号，所以两边的对照表能共用。
using System.Text;

namespace DeskHub.Core;

public static partial class Strings
{
    /** "zh" 或 "en" */
    public static string Lang { get; set; } = "zh";
    public static bool En => Lang == "en";

    public static string Lookup(string zh)
    {
        if (!En) return zh;
        if (Win.TryGetValue(zh, out var w)) return w;
        return Mac.TryGetValue(zh, out var m) ? m : zh;
    }

    /** 把 %@ 依次换成参数，%% 换成 % */
    public static string Format(string fmt, params object?[] args)
    {
        var sb = new StringBuilder();
        int k = 0;
        for (int i = 0; i < fmt.Length; i++)
        {
            if (fmt[i] == '%' && i + 1 < fmt.Length)
            {
                if (fmt[i + 1] == '@') { sb.Append(k < args.Length ? Convert.ToString(args[k], System.Globalization.CultureInfo.InvariantCulture) : ""); k++; i++; continue; }
                if (fmt[i + 1] == '%') { sb.Append('%'); i++; continue; }
            }
            sb.Append(fmt[i]);
        }
        return sb.ToString();
    }

    /** 所有对照表里的条目数（测试用：加载时如果有重复键会直接报错） */
    public static int Count => Mac.Count + Win.Count;
}

public static class I18n
{
    public static string L(string zh) => Strings.Lookup(zh);
    public static string L(string fmt, params object?[] args) => Strings.Format(Strings.Lookup(fmt), args);
}
