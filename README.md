# WeChat OCR Auto-Reply（iOS 原型 v0.1）

非越狱的 iOS 微信 OCR 自动回复原型：**ReplayKit 抓屏 → Vision 中文 OCR → 你的后端生成回复 → 剪贴板 + 本地通知半自动发送**。

设计原则：不 hook、不注入、不走协议（防封号，见下）；发送端保持人工确认。

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
│  Vision OCR（zh-Hans 准确模式）                                │
│      ▼  文本没变则跳过                                          │
│  POST 你的后端  {device_id, session, screen_text, captured_at} │
│      ▼                                                        │
│  {action: "reply", reply: "..."}                              │
│      ├─► App Group 共享存储（主 App 控制台展示）                 │
│      ├─► UIPasteboard.general.string = reply                  │
│      └─► 本地通知："已复制 → 打开微信粘贴发送"                   │
│                                                              │
│  主 App：配置后端 / 消息流 / 一键复制 / 打开微信                  │
└──────────────────────────────────────────────────────────────┘
                     │ HTTP
                     ▼
          ┌─────────────────────┐
          │  你的现有后端         │  ◄── 本项目默认不强制自带服务端
          │  （返回回复文本）      │      server/ 目录是参考实现 + mock
          └─────────────────────┘
```

## 目录

```
wechat-ocr-autoreply/
├── server/                    # 参考服务端（FastAPI + OpenAI 兼容 LLM）
│   ├── main.py                #   /api/v1/analyze、/health、白名单/限频 API
│   ├── llm.py                 #   LLMClient（默认 DeepSeek）+ MockLLM
│   ├── rate_limiter.py        #   小时/天限额 + 最小间隔 + 活跃时段
│   ├── config.py / models.py
│   └── test_server.py         #   12 个用例，全部通过（python test_server.py）
└── ios/                       # iOS 工程（XcodeGen）
    ├── project.yml
    ├── README.md              #   Mac 上搭建步骤
    └── WeChatOCRAutoReply/
        ├── Shared/            #   AppConfig / 共享存储（App Group）
        ├── App/               #   主 App：设置、控制台、复制、打开微信
        └── Broadcast/         #   录屏扩展：OCR + 上传 + 通知
            └── APIClient.swift  ← ★ 对接你后端只改这一个文件 ★
```

## 对接你现有的后端（重点）

iOS 端与后端的契约集中在 `ios/WeChatOCRAutoReply/Broadcast/APIClient.swift` 一个文件里：

| | 默认契约 |
|---|---|
| 方法 | `POST {serverURL}{analyzePath}` |
| 鉴权 | `Authorization: Bearer {token}`（token 可空） |
| 请求 | `{"device_id", "session", "screen_text", "captured_at"}` |
| 响应 | `{"action": "reply"\|"ignore", "reply": "...", "reason": "..."}` |

如果你的后端接口不同，改 `AnalyzeResponseBody` 字段名 + `analyze()` 里的请求组装即可，其他文件不用动。服务器地址/路径/token 在主 App「设置」页可配，不用重新编译。

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

真机运行 → 设置里填后端地址 → 微信聊天界面 → 控制中心长按录屏选「WeChatOCR」→ 对方来消息自动出回复 → 复制 → 粘贴发送。

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
