#!/bin/zsh
# 跑纯逻辑测试：Core + Tests 编译成一个小程序直接运行（不需要窗口，也不联网）
set -e
cd "$(dirname "$0")"
mkdir -p build
./scripts/swiftc.sh -Onone Sources/Core/*.swift Tests/*.swift -o build/tests
./build/tests
