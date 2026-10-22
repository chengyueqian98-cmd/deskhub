#!/bin/zsh
# 编译并组装 .app：build/桌面信息中心.app。加 --install 装到 ~/Applications 并签名（会先关掉正在运行的原生版）。
set -e
cd "$(dirname "$0")"
NAME="桌面信息中心"
APP="build/$NAME.app"
mkdir -p build
./scripts/swiftc.sh -O -whole-module-optimization Sources/Core/*.swift Sources/App/*.swift -o build/DeskHub
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp build/DeskHub "$APP/Contents/MacOS/DeskHub"
cp Info.plist "$APP/Contents/Info.plist"
cp Resources/icon.icns "$APP/Contents/Resources/icon.icns"
echo "已编译：$APP（$(du -sh "$APP" | cut -f1)）"

[[ "$1" == "--install" ]] || exit 0
# 桌面在 iCloud 里，会给 app 加上 Finder 属性导致签名失效，所以装到 ~/Applications 再签
DEST="$HOME/Applications/$NAME 原生版.app"
KC="$HOME/Library/Keychains/desktop-hub-signing.keychain-db"
PASSFILE="$HOME/.config/desktop-hub/keychain-pass"
CERT="DeskHub Local Signing"
pkill -f "$NAME 原生版.app/Contents/MacOS/DeskHub" 2>/dev/null || true
rm -rf "$DEST"
ditto --norsrc --noextattr "$APP" "$DEST"
xattr -cr "$DEST"
if [[ -f "$KC" && -f "$PASSFILE" ]]; then
  security unlock-keychain -p "$(cat "$PASSFILE")" "$KC"
  HASH=$(security find-certificate -c "$CERT" -Z "$KC" | awk '/SHA-1/{print $3}')
  codesign --force -s "$HASH" --keychain "$KC" "$DEST"
  echo "签名：$CERT（固定，系统权限不用每次重新允许）"
else
  codesign --force -s - "$DEST"
  echo "签名：ad-hoc"
fi
codesign -v "$DEST"
echo "已安装：$DEST"
