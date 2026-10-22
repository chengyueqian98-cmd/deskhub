#!/bin/zsh
# 出给别人用的安装包：build/DeskHub-<版本>.dmg（里面是 App + 「应用程序」快捷方式 + 第一次打开的说明）。
# 没有 Apple 开发者账号，所以用 ad-hoc 签名：别人第一次打开时系统会拦一下，说明文件里写了怎么放行。
# 签名要在桌面（iCloud）以外的地方做，否则 Finder 属性会让签名失效。
set -e
cd "$(dirname "$0")/.."
./build.sh
VER=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Info.plist)
STAGE=$(mktemp -d /tmp/deskhub-dmg.XXXXXX)
ditto --norsrc --noextattr "build/桌面信息中心.app" "$STAGE/桌面信息中心.app"
xattr -cr "$STAGE/桌面信息中心.app"
codesign --force --deep -s - "$STAGE/桌面信息中心.app"
ln -s /Applications "$STAGE/Applications"
cat > "$STAGE/第一次打开看这里 · Read me first.txt" <<'EOF'
【安装】把「桌面信息中心」拖进「Applications（应用程序）」。

【第一次打开】这个软件没有付费的 Apple 开发者签名，所以 macOS 会说「无法验证开发者」：
  1. 双击打开一次，看到提示后点「完成」；
  2. 打开「系统设置 → 隐私与安全性」，拉到最下面，点「仍要打开」；
  3. 再打开一次，点「打开」。之后就不会再问了。
（代码全部开源在 GitHub 上，你可以自己检查或自己编译。）

[Install] Drag Desk Hub into Applications.

[First launch] This app isn't signed with a paid Apple Developer ID, so macOS will say it can't verify the developer:
  1. Open it once and click Done;
  2. Go to System Settings → Privacy & Security, scroll down and click "Open Anyway";
  3. Open it again and click Open. You won't be asked again.
(The source code is on GitHub — feel free to inspect or build it yourself.)
EOF
OUT="build/DeskHub-$VER.dmg"
rm -f "$OUT"
hdiutil create -volname "桌面信息中心 $VER" -srcfolder "$STAGE" -ov -format UDZO "$OUT" >/dev/null
rm -rf "$STAGE"
echo "安装包：$OUT（$(du -h "$OUT" | cut -f1)）"
