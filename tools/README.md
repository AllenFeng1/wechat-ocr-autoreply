# tools/ —— 推送前本地类型检查（preflight）

## 解决什么问题

以前的工作流是：改代码 → 推送 → GitHub Actions 编译 → **失败** → 看日志 → 修 → 再推送。
每次打包都要来回修一两轮编译错误（`self.` 漏写、API 签名不熟、可选链层级看错……），
因为 Windows 上没有 Xcode，CI 是第一个真正编译代码的地方。

`tools/preflight.sh`（Git Bash）和 `tools/preflight.ps1`（PowerShell）把编译检查
**前移到本地**：推送前跑一次，两个 Xcode 目标（App + 广播扩展）全部类型检查通过，
才允许推送。CI 失败应该从此成为罕见事件。

## 用法

```bash
# Git Bash
bash tools/preflight.sh

# 或 PowerShell
powershell -ExecutionPolicy Bypass -File tools\preflight.ps1
```

输出 `✅ preflight 通过：两个目标均可编译，可以推送` 才能推；
有 error 会原样列出（文件:行:列 与 Xcode 一致），非零退出码。

## 前提

安装 Swift for Windows 工具链（一次性，约 1GB）：

```
winget install --id Swift.Toolchain
```

脚本会自动在 `%LOCALAPPDATA%\Programs\Swift\` 下找 swiftc 和 Windows.sdk；
也可以用环境变量 `SWIFTC` / `SWIFT_SDK` 手动指定。

## 原理

`tools/swift-stubs/` 下是一组 **iOS SDK 桩模块**（CoreGraphics / UIKit /
Vision / ReplayKit / SwiftUI / PhotosUI / os / CoreImage / UserNotifications /
Combine / CoreMedia / Network）。它们只复刻 App 代码实际用到的 API 形状，
编译成 `.swiftmodule` 后作为 `-I` 搜索路径，让 `swiftc -typecheck`
在 Windows 上完整检查两个目标的全部源码：

```
swift-stubs/*.swift ──emit-module──▶ build/preflight-modules/*.swiftmodule
                                              │
ios/WeChatOCRAutoReply/{App,Shared}/*.swift ──┼─typecheck─▶ WeChatOCRAutoReply 目标
ios/WeChatOCRAutoReply/{Broadcast,Shared}/*.swift ─typecheck─▶ BroadcastExtension 目标
```

**已验证与 CI 对齐**（两次反向验证）：
1. 把 CI 日志里的错误（SampleHandler.swift:54 的 `self.` 缺失）重新注入源码，
   preflight 报出完全相同的 `文件:行:列` 和错误信息；
2. 补 Network 桩后，preflight 立刻报出 CI 上那个 8 秒失败的真凶——
   `ZXTouchClient.swift:53:32: error: incorrect argument label in call
   (have 'host:port:uses:', expected 'host:port:using:')`。

### 桩模块的维护规则

改 iOS 代码时如果用到**新的 SDK API**，preflight 可能报
`cannot find type 'X' in scope` / `value of type 'X' has no member 'y'`。
这可能是两种情况：

1. 真写错了 → 直接修；
2. 桩没覆盖到这个 API → 在对应的桩模块里按**真实签名**补上
   （拿不准就去查 Apple 文档，签名必须一致，否则本地会漏报真实错误）。

几个已经踩过的坑，写桩时特别注意：

- `loadTransferable(type:)` 返回 `T?`（Swift 5 起 `try?` 会拍平嵌套可选，
  所以 `guard let data = try? await item.loadTransferable(...)` 拿到的是 `T` 不是 `T?`）；
- `os_log` 的字符串插值 `appendInterpolation` 必须带
  `@autoclosure @escaping`，否则复现不出「插值里访问 self 属性必须显式 self.」；
- `CFDataGetBytePtr` 返回隐式解包可选（`UnsafePointer<UInt8>!`）；
- SwiftUI 的 `.secondary` / `.borderless` 等上下文成员，必须声明在
  `extension X where Self == 具体类型` 的约束扩展里；
- Windows corelibs Foundation 自带 CGFloat / CGRect / CGPoint / CGSize
  （但缺隐式 Int 转换），URLSession 在 `FoundationNetworking` 模块里，
  `FileManager.containerURL(forSecurityApplicationGroupIdentifier:)` 不存在
  （App 代码已用 `#if os(iOS) || os(macOS)...` 平台守卫处理）。

## 边界（什么它查不了）

- 真机运行时行为（Vision OCR 效果、ReplayKit 帧率、内存）；
- Storyboard / 资源文件 / Info.plist / entitlements（本次未涉及，有的话要另外校验）；
- 链接期问题（本项目是归档 + 重签名，签名问题只有 CI 能发现）；
- Swift 6 严格并发是**警告**（项目是 Swift 5.9 模式）。APIClient 里有几处
  `mutation of captured var` 的 Sendable 警告，现在不阻塞，将来升级 Swift 6 时要处理。

### ⚠️ 两个真实发生过的盲区（2026-10-17 连续两次 CI 失败后补的课）

**1. `#if canImport(...)` 会把 iOS 代码整段藏起来**
ZXTouchClient 的 TCP 实现整段包在 `#if canImport(Network)` 里，Windows 上
没有 Network 模块 → 预检时整段被跳过 → `NWConnection(host:port:uses:)`
（正确是 `using:`）这个错误本地永远发现不了。**对策**：新增
`tools/swift-stubs/Network.swift`，让 `canImport(Network)` 在预检时为真。
以后凡是用 `#if canImport(X)` 包裹的平台代码，都要给 X 建桩，否则等于没检查。

**2. API 可用性（availability）在 Windows 上无法检查**
swiftc 没有 iOS 部署目标的概念，`@available(iOS 17.0, *)` 的桩 API 在
Windows 上照用不报错。而本工程 `IPHONEOS_DEPLOYMENT_TARGET = 16.0`，
用到 iOS 17 专属 API（如 `onTapGesture(count:coordinateSpace:perform:)`）
在 CI 上直接编译失败。**对策（人工规则）**：用到**任何**不熟悉的 SwiftUI /
框架 API 时，先查 Apple 文档确认最低版本 ≤ 16.0 再用。桩里能给高版本 API
标 `@available` 就标上，至少起提示作用。

已按版本核对过安全的（都 ≤ 16.0，其中带 * 的经 00:28 成功构建实证）：
`.controlSize(.small)`*、`.navigationBarTrailing`*、`PhotosPicker`(16.0)、
`.foregroundStyle`(15.0)、`Button(role:)`(15.0)、`onChange` 单参数版(14.0)、
`@Environment(\.dismiss)`(15.0)、`ignoresSafeArea`(14.0)。
