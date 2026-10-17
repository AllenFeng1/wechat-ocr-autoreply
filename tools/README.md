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
Combine / CoreMedia）。它们只复刻 App 代码实际用到的 API 形状，
编译成 `.swiftmodule` 后作为 `-I` 搜索路径，让 `swiftc -typecheck`
在 Windows 上完整检查两个目标的全部源码：

```
swift-stubs/*.swift ──emit-module──▶ build/preflight-modules/*.swiftmodule
                                              │
ios/WeChatOCRAutoReply/{App,Shared}/*.swift ──┼─typecheck─▶ WeChatOCRAutoReply 目标
ios/WeChatOCRAutoReply/{Broadcast,Shared}/*.swift ─typecheck─▶ BroadcastExtension 目标
```

**已验证与 CI 对齐**：把 CI 日志里的错误（SampleHandler.swift:54 的
`self.` 缺失）重新注入源码，preflight 报出完全相同的 `文件:行:列` 和错误信息。

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
