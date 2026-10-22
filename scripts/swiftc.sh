#!/bin/zsh
# 包一层 swiftc：这台电脑的命令行工具里残留了一个 2023 年的 usr/include/swift/module.modulemap，
# 和新版的 bridging.modulemap 重复定义 SwiftBridging，导致 SwiftUI / EventKit 一个都编译不了。
# 不改系统文件（要 sudo），而是用一层虚拟文件覆盖把旧的那个换成空文件，只对这次编译生效。
set -e
HERE="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$HERE/build/.vfs"
mkdir -p "$TMP"
OLD=/Library/Developer/CommandLineTools/usr/include/swift/module.modulemap
EXTRA=()
if [[ -f "$OLD" && -f /Library/Developer/CommandLineTools/usr/include/swift/bridging.modulemap ]]; then
  : > "$TMP/empty.modulemap"
  cat > "$TMP/vfs.yaml" <<EOF
{ "version": 0, "case-sensitive": "false", "roots": [ { "name": "$OLD", "type": "file", "external-contents": "$TMP/empty.modulemap" } ] }
EOF
  EXTRA=(-vfsoverlay "$TMP/vfs.yaml" -Xcc -ivfsoverlay -Xcc "$TMP/vfs.yaml")
fi
exec swiftc -swift-version 5 -target arm64-apple-macos14.0 "${EXTRA[@]}" "$@"
