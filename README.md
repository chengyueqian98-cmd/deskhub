# 桌面信息中心 · Desk Hub

**一个只在重要时刻说话的 Mac 桌面。** 时钟、天气、日程、行情、邮件安静地铺在壁纸两侧，中间留给你；管家只在真正重要的时候出声。按 `⌃⌥空格` 打开可以操作的那一层。

*A Mac desktop that only speaks up when it matters. English below.*

![下载量](https://img.shields.io/github/downloads/chengyueqian98-cmd/deskhub/total?label=下载)
![最新版本](https://img.shields.io/github/v/release/chengyueqian98-cmd/deskhub?label=版本)

![桌面](docs/screenshots/desk.png)

## 特点

- **原生、轻量**：SwiftUI 写的，安装包 6 MB，常驻内存约 50 MB，空闲时 CPU 接近 0。
- **桌面层 + 浮层**：桌面层在壁纸之上、图标之下，只显示不打扰；`⌃⌥空格` 呼出浮层，可以点、可以问、可以改布局。
- **16 种组件，同一种可以加好几个**：时钟、天气、日历、待办（提醒事项）、邮件、行情、新闻、订阅（任意 RSS / Atom）、世界时钟、倒数日、加密货币、GitHub、照片、番茄钟、管家……每个各自设置（两个行情组件，一个看 A 股、一个看美股）。
- **像 iOS 小组件那样摆**：小 / 中 / 大几档，拖动吸附，自动避让，挪走后被挤开的会自己回去。
- **管家只说重要的事**：「可执行 × 意外」两个维度判断，每天最多打断你一次；谁的邮件重要由你自己定，也可以让 AI 帮你判断。
- **能聊天、能办事**（可选）：填一个 DeepSeek 的 Key，或用本机的 Claude Code。说「把腾讯加进自选」「明早 8 点提醒我交作业」，它列出要做的事，**你点了才执行**。
- **首次引导**：选语言、选身份（学生 / 上班 / 投资 / 极简）就摆好一套。中文、English 都有。
- **主题**：强调色、字号、两侧渐隐浓淡、线条或卡片风格；多显示器每块屏一套布局。
- **自动检查更新**：有新版本时在浮层右上角提示一下（只问 GitHub「最新版本是几号」，不带任何个人信息，不会自动下载安装）。
- **隐私**：没有账号、没有服务器、不收集任何数据。日历、邮件只读；邮件正文只有你点开或让管家概括时才读。代码全部开源。

## 安装

1. 到 [Releases](../../releases) 下载最新的 `DeskHub-x.y.z.dmg`，把 App 拖进「应用程序」。
2. **第一次打开会被系统拦下**（这个软件没有付费的 Apple 开发者签名）：打开「系统设置 → 隐私与安全性」，拉到最下面点「仍要打开」。之后就不会再问了。
3. 需要 macOS 14 或更新，Apple 芯片（M1 及以后）。

## 自己编译

只需要 Xcode 命令行工具（`xcode-select --install`），不需要 Xcode：

```bash
./test.sh                 # 跑测试
./build.sh                # 编译到 build/桌面信息中心.app
./scripts/make-dmg.sh     # 出安装包
```

推一个 `v` 开头的标签，GitHub Actions 会自动测试、编译、发布到 Releases。

## 数据来源

行情：新浪财经公开接口（延迟，仅供参考）· 天气：Open-Meteo · 加密货币：CoinGecko · 新闻：各家公开 RSS · 日历 / 提醒事项：系统 EventKit · 邮件：Mac「邮件」App（AppleScript，只读）。都不需要注册。

**本软件只做信息展示和提醒，不构成任何投资建议，不会替你下单。**

---

## English

**Desk Hub** puts your clock, weather, calendar, to-dos, mail, stocks and news quietly on both sides of your wallpaper, and a butler that only speaks up when something really needs you. Press `⌃⌥Space` for the interactive overlay.

- Native SwiftUI: 6 MB download, ~50 MB memory, near-zero idle CPU.
- 16 widget types, add several of the same kind with their own settings; iOS-style sizes with snapping and auto-arrange.
- Optional AI (bring your own DeepSeek key, or use a local Claude Code): ask questions or say "remind me at 8 tomorrow" — it shows a confirmation card and only acts after you tap Run.
- Apple-style first-run tour, full English and Chinese UI, themes, multi-display layouts, update notifications.
- No account, no server, no tracking. Open source under MIT.

**Install:** download the DMG from Releases and drag the app to Applications. On first launch macOS will block it (no paid Developer ID) — go to System Settings → Privacy & Security and click "Open Anyway". Requires macOS 14+ on Apple silicon.

**Not investment advice.** Market data is delayed and for display only.

## License

MIT
