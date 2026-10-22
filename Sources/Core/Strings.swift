// 中英文界面：首次引导里选语言（设置里也能改）。界面上的中文原文就是「键」，英文版在 EN 表里查；
// 查不到就照样显示中文——所以新加的文字忘了翻译也不会显示成空白。
import Foundation

var appLang = "zh"

func L(_ s: String) -> String { appLang == "en" ? (EN[s] ?? s) : s }

/** 带参数的：L("今天 %@ 件", "3") */
func L(_ s: String, _ args: CVarArg...) -> String { String(format: L(s), arguments: args) }
