# iOS 端搭建说明（在 Mac 上操作）

## 0. 想要 IPA？三条路径

| 路径 | 需要 | 产物 |
|---|---|---|
| **A. 云构建（无 Mac）** | GitHub 账号 | Actions 自动产出**无签名 IPA** → AltStore 安装 |
| **B. Mac 一键脚本** | Mac + Xcode | `./build-ipa-mac.sh` 直接出 IPA |
| **C. Xcode 手动** | Mac + Xcode | Product → Archive → Export |

### A. 云构建（推荐，不需要 Mac）

1. 把整个 `wechat-ocr-autoreply` 目录推到 GitHub（公开仓库免费；私有仓库每月 2000 分钟免费额度，够用）
2. 在仓库 Actions 页面点 **Run workflow** 手动构建（**免费 Apple ID 必须勾选 `free_account`**；不监听 push 自动触发——自动触发无法区分账号类型，默认配置产出的 IPA 免费账号用不了）
3. 构建成功后下载 artifact：`WeChatOCRAutoReply-unsigned-ipa`
4. 安装到 iPhone：
   - Windows 装 [AltStore](https://altstore.io/)（免费，支持 Windows）
   - iPhone 装 AltStore（同 Apple ID 免费证书，7 天有效，到期 AltStore 一键续期）
   - AltStore → 左上 `+` → 选下载的 `WeChatOCRAutoReply-unsigned.ipa` → 安装
5. **免费 Apple ID** 用不了 App Group：手动触发 workflow 时勾选 `free_account` 选项（等价于本地 `cp project.freeaccount.yml project.yml && xcodegen generate`）。该模式下录屏扩展读不到主 App 的设置，使用代码默认服务器地址（改 `Shared/SharedTypes.swift` 里 `AppConfig.default.serverURL`）

### B. Mac 一键脚本

```bash
cd ios
./build-ipa-mac.sh                        # 无签名 IPA（配 AltStore 用）
TEAM_ID=你的TeamID ./build-ipa-mac.sh     # 自动签名并导出 IPA（Xcode→Settings→Accounts 查看 Team ID）
```

### C. Xcode 手动

```bash
cd ios && xcodegen generate && open WeChatOCRAutoReply.xcodeproj
# 真机运行调试后：Product → Archive → Distribute App → Development → 导出 .ipa
```

---

## 1. 前置条件

- macOS + Xcode 15+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)：`brew install xcodegen`
- 真机一台（iOS 16+），**录屏广播扩展只能在真机测试**
- 账号分两种：
  - **付费开发者账号（$99/年）**：完整功能。需要在开发者后台创建 App Group：`group.com.example.wechatocr`（或改成你的 prefix）
  - **免费个人账号**：不能用 App Group。生成工程前先 `cp project.freeaccount.yml project.yml`（spec 已准备好），扩展会用默认配置运行，服务器地址写死在 `Shared/SharedTypes.swift` 的 `AppConfig.default` 里

## 2. 生成并打开工程

```bash
cd ios
xcodegen generate
open WeChatOCRAutoReply.xcodeproj
```

## 3. 签名

- 两个 target（WeChatOCRAutoReply / BroadcastExtension）都在 Xcode → Signing & Capabilities 里选你的 Team
- Bundle ID 全局唯一：默认 `com.allenfeng1.wechatocr`（已按 GitHub 用户名定制，不会撞名）。如仍要改：`project.yml` 的 `bundleIdPrefix` + 两处 `PRODUCT_BUNDLE_IDENTIFIER`，**同时**改 `Shared/ConfigStore.swift` 里的 `appGroupId`（两个 entitlements 文件也要同步）

## 4. 运行

1. 真机运行主 App，进「设置」填你后端的地址/路径/token，保存
2. 打开微信，进入一个聊天界面
3. 下拉控制中心 → 长按录屏按钮 → 选择「WeChatOCR」→ 开始直播
4. 对方发来新消息后：OCR 识别 → 上传你的后端 → 回复自动写入剪贴板 + 弹本地通知
5. 点通知或回主 App 点「打开微信」→ 长按输入框粘贴 → 发送

> iOS 16+ 跨 App 读取剪贴板时系统会弹「允许粘贴」，这是系统行为，点一下即可，不影响账号安全。

## 5. 调试技巧

- 扩展的日志：Xcode → Debug → Attach to Process → `BroadcastExtension`，或 `log stream --predicate 'subsystem contains "wechatocr"'`
- 先在主 App 设置里把服务器指向 `server/` 的 mock 服务（`LLM_API_KEY` 留空即可用 MockLLM 跑通全链路）
- OCR 识别不准时：微信字体大小、深色模式、消息密度都会影响；`recognitionLevel = .accurate` 已是最佳精度，仍不满意可改 `.fast` 提升帧率

## 6. 已知限制

- 会话名是从屏幕最顶部 OCR 文本粗提取的，白名单匹配是 best-effort，严格白名单请在后端做
- 微信升级若改版导航栏结构，只需重测 session 提取逻辑
- 扩展内存上限约 50MB，已按 1 秒/帧节流；不要在扩展里缓存图片
