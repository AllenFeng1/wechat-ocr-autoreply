# WeChat OCR Auto-Reply（iOS · 对接 AnamneChat 后端）

非越狱的 iOS 微信 OCR 自动回复原型：**ReplayKit 抓屏 → Vision OCR + 气泡颜色分类 → AnamneChat（MiraMate）后端生成回复 → 剪贴板 + 本地通知半自动发送**。

设计原则：不 hook、不注入、不走协议（防封号）；发送端保持人工确认；功能与 PC 客户端对齐。

> **v0.2 起对接真实后端**（https://chat.anamne.top）。契约、改动清单、绑定模型见 **[后端对接说明-AnamneChat.md](后端对接说明-AnamneChat.md)**。
> `server/` 目录的 FastAPI 参考实现（`/api/v1/analyze`）已废弃，仅作历史参考。

## 架构

```
┌──────────────────────────────────────────────────────────────┐
│  iPhone（无需越狱）                                            │
│                                                              │
│  微信聊天界面                                                  │
│      │  ReplayKit 广播扩展（用户手动开启录屏并选择本 App）        │
│      ▼                                                        │
│  SampleHandler.processSampleBuffer ── 1秒/帧节流               │
│      ▼                                                        │
│  Vision OCR（zh-Hans 准确模式）→ 气泡颜色分类（绿=自己/她=对方）   │
│      ▼  会话名 + 末尾连续对方消息；内容签名去重                   │
│      ▼                                                        │
│  会话名 → 好友绑定表 → 自动匹配 nickname/remark → friend_id     │
│      ▼  未绑定则通知，不生成、不自动建档                          │
│  POST /api/chat/{fid}/generate  {incoming, action:"auto"}      │
│      ▼                                                        │
│  {reply, group_id, emotion_detected, error?}                   │
│      ├─► 剪贴板（多行 \n 保留，逐条粘贴发送）                     │
│      ├─► 本地通知："回复已就绪"                                 │
│      └─► App Group / 命名剪贴板 → 主 App 控制台                  │
│                                                              │
│  主 App：登录 / 测试连接 / 好友刷新 / 会话绑定 / 控制台           │
└──────────────────────────────────────────────────────────────┘
                     │ HTTPS
                     ▼
          ┌─────────────────────────────┐
          │  AnamneChat 后端             │
          │  /api/auth/login            │
          │  /api/friends               │
          │  /api/chat/{fid}/generate   │  ◄── 人设/记忆/分条全在服务端
          │  /api/chat/{fid}/outcome    │
          └─────────────────────────────┘
```

## 目录

```
wechat-ocr-autoreply/
├── 后端对接说明-AnamneChat.md   # ★ 本次对接的契约 / 改动 / 绑定模型 / 排错
├── server/                    # 参考服务端（已废弃，历史参考）
├── ios/                       # iOS 工程（XcodeGen）
│   ├── project.yml
│   ├── README.md              #   Mac 上搭建步骤
│   └── WeChatOCRAutoReply/
│       ├── Shared/            #   AppConfig / 好友绑定 / 共享存储 / APIClient（★ 后端契约只在这一个文件，主 App 与扩展共用）
│       ├── App/               #   主 App：登录、绑定、控制台
│       └── Broadcast/         #   录屏扩展：OCR + 气泡分类 + generate + 通知
└── 上手教程-从零到IPA.md       # Windows 用户出 IPA + 安装全流程
```

## 对接 AnamneChat 后端（v0.2）

iOS 端与后端的所有交互都在 `ios/WeChatOCRAutoReply/Shared/APIClient.swift` 一个文件里（主 App 和录屏扩展共用，故放在 Shared）：

| 接口 | 说明 |
|---|---|
| `POST /api/auth/login` | `{username, password}` → `{token}` |
| `GET /api/friends` | 好友档案（Bearer） |
| `POST /api/friends` | 新建档案（仅用户显式触发） |
| `POST /api/chat/{fid}/generate` | **核心**：`{incoming, action:"auto"}` → `{reply, group_id, emotion_detected, error?}` |
| `POST /api/chat/{fid}/outcome` | sent/edited/cancelled 回传 |

服务器地址、账号密码都在 App 设置页可配，不用重新编译。完整契约与排错见 [后端对接说明-AnamneChat.md](后端对接说明-AnamneChat.md)。

## 快速开始

### A. 先跑通参考服务端（可选，用于联调）

```bash
cd server
cp .env.example .env        # 填 LLM_API_KEY；不填则用 MockLLM 跑通链路
pip install -r requirements.txt
python test_server.py       # 跑测试
uvicorn main:app --host 0.0.0.0 --port 8000
```

服务端内置防封号策略：小时/天限额、最小间隔、活跃时段（默认 8-23 点）、白名单。**这些参数应按你的实际节奏调松或调紧**，最终风控以你的后端为准。

### B. iOS 端

见 [ios/README.md](ios/README.md)。摘要：

```bash
cd ios && xcodegen generate && open WeChatOCRAutoReply.xcodeproj
```

真机运行 → 设置页登录后端 → 绑定会话 → 微信聊天界面 → 控制中心长按录屏选「WeChatOCR」→ 对方来消息自动出回复 → 复制 → 粘贴发送。

### 想要 IPA（装到 iPhone）

iOS 只能在 macOS 上编译，这里准备了三条路（详见 [ios/README.md](ios/README.md)）：

1. **云构建（不用 Mac）**：推到 GitHub → Actions 自动产出无签名 IPA → Windows 装 AltStore 用免费 Apple ID 装上 iPhone（7 天一续）
2. **Mac 一键脚本**：`cd ios && ./build-ipa-mac.sh`（带 `TEAM_ID=xxx` 则自动签名导出）
3. **Xcode 手动**：Archive → Distribute → Export

## 防封号清单（来自调研报告，v0.1 已落实的标 ✅）

- ✅ 纯视觉方案：不 hook / 不注入 / 不走协议
- ✅ 帧节流（1s）+ 画面无变化跳过 + 客户端最小上传间隔
- ✅ 服务端限额（默认 20 条/小时、50 条/天、最小间隔 30s）
- ✅ 活跃时段限制（默认 8-23 点，不 24 小时挂机）
- ✅ 会话白名单
- ✅ 半自动发送：人点最后一下
- ⬜ 回复延迟拟人化（当前是识别到就上传，发送时机由你手动控制，天然带人的延迟；如需更严格可在后端加"生成后延迟 N 秒再推送"）
- ⬜ 只用实名老号（账号层面，见调研报告）

## 合规提醒

个人微信的一切自动化行为均违反《微信软件许可及服务协议》，官方明令禁止。本项目仅限个人学习研究；商用/客服场景请走企业微信官方 API。

## 诚实声明

- iOS 代码在交付环境（Windows）**未经编译验证**，首次在 Mac/GitHub Actions 构建时可能需要修 1-2 个小错（签名、Bundle ID 冲突等），构建日志发我即可快速修
- 服务端代码已在本机跑通全部 12 个测试用例
