// 测试运行器：命令行工具里没有 XCTest，这里用一个最小的断言框架。`./test.sh` 编译 Core + 本目录并运行。
// 用例从 Electron 版 test/*.test.js 逐条移植——两边规则必须一致。
import Foundation

var passed = 0
var failed: [String] = []
var current = ""

func test(_ name: String, _ body: () -> Void) {
  current = name
  let before = failed.count
  body()
  if failed.count == before { passed += 1 }
}

func ok(_ cond: Bool, _ msg: String = "", file: String = #file, line: Int = #line) {
  if !cond { failed.append("✗ \(current)\n    \((file as NSString).lastPathComponent):\(line) \(msg)") }
}

func eq<T: Equatable>(_ a: T, _ b: T, _ msg: String = "", file: String = #file, line: Int = #line) {
  if a != b { failed.append("✗ \(current)\n    \((file as NSString).lastPathComponent):\(line) 期望 \(b)，实际 \(a) \(msg)") }
}

layoutTests()
briefTests()
candidateTests()
planTests()
marketTests()
newsMailTests()
miscTests()
batteryNotChargingTest()
aiTests()
extraTests()

print("通过 \(passed) 项，失败 \(failed.count) 项")
for f in failed { print(f) }
exit(failed.isEmpty ? 0 : 1)
