# 后端对接说明：AnamneChat（MiraMate PC API）

> iOS 端「微信 OCR 自动回复」对接你现有后端（https://chat.anamne.top）的完整契约与改动清单。
> 契约来源：源码交接包 `01-后端源码/src/MiraMate/web_api/pc_api.py + auth_api.py`，
> 调用方参照 `02-前端源码`（PC 客户端）的 `core/backend_client.py` / `core/engine.py` / `app/settings.py`。
> 线上已验证：`/api/health` 200、`/api/friends` 无 token 401、登录错误 401 `{"detail":"用户名或密码错误"}`。

---

## 1. 后端接口（iOS 端全部走这些）

| # | 接口 | 请求 | 响应 | 用途 |
|---|---|---|---|---|
| 1 | `POST /api/auth/login` | `{username, password}` | `{ok, token}`；401 `{"detail":...}` | 登录换 token |
| 2 | `GET /api/friends` | Bearer token | `[{id, nickname, remark, ...}]` | 好友档案列表 |
| 3 | `POST /api/friends` | `{nickname, remark?}` | `{id, nickname, remark}` | 新建档案（**仅用户显式触发**） |
| 4 | `POST /api/chat/{fid}/generate` | `{incoming, action:"auto", group_id:""}` | `{reply, reply_raw, group_id, emotion_detected, icebreaker?, error?}` | **核心：生成回复** |
| 5 | `POST /api/chat/{fid}/outcome` | `{action:"sent"\|"edited"\|"cancelled", final_text}` | `{ok}` | 用户实际处理结果回传 |

除登录外全部带 `Authorization: Bearer <token>`。

### generate 的响应语义（与 PC 端 engine.py 一致）

- `reply` 里的 **`\n` = 建议分多条发**（PC 端 split_reply 逐条发；iOS 端分行展示、可单行复制）
- `emotion_detected: true` → reply 为空，后端要人工介入。iOS 端**按 PC 端做法自动补第二轮**：`action=plain` + `force_mood=comfort`，带第一轮的 `group_id`（不带 incoming，不会写重历史）
- `jev_pending: true` → 同理补第二轮 `action=jev_inject`
- `error` 非空 → 后端明确失败（禁句被丢弃等），**不重试**
- `icebreaker: true` → 新好友破冰话术
- ⚠️ **有副作用**：incoming 会入库。同一批内容绝不反复调（iOS 端有「内容签名去重」+ 节流）

---

## 2. iOS 端改了什么（相对 v0.1）

| 文件 | 变化 |
|---|---|
| `Broadcast/APIClient.swift` | **整个重写**为 `BackendClient`：login / listFriends / createFriend / generate（含第二轮补拍）/ reportOutcome / healthCheck。旧的 `/api/v1/analyze` 契约已废弃 |
| `Broadcast/OCRPipeline.swift` | **重写**：Vision OCR 框 + 像素取色分类气泡（绿泡=自己、非绿高对比=对方、置中=系统提示、杂色=图片里的字）；会话名提取（最上一行最左文本，去群人数后缀）；时间戳/UI 噪声过滤；`incoming` = 末尾连续对方消息（\n 连接，同 PC `_tail_from_her`） |
| `Broadcast/SampleHandler.swift` | 重写流程：解析 → 内容签名去重 → 白名单 → 解析好友 → generate → 剪贴板 + 通知 + 控制台 |
| `Shared/SharedTypes.swift` | `AppConfig` 增加 `username/password/friendBindings`；新增 `FriendProfile`、`GenerateResult`、`ParsedLine`、`BubbleKind`；`ReplySuggestion` 增加 `friendId/outcome/note` 和多行 `lines` |
| `Shared/ConfigStore.swift` | 重写：配置三层通道（App Group → 命名剪贴板 → 代码默认值）+ 会话绑定表 + 好友缓存 |
| `Shared/SharedStore.swift` | 适配新 ConfigStore；免费模式静默降级 |
| `App/MessageStore.swift` | 增加 login / testConnection / refreshFriends / createAndBind / bind / unbind / reportOutcome |
| `App/ContentView.swift` | 设置页：服务器地址、测试连接、用户名密码登录、好友刷新、**会话绑定**（下拉选择/新建/解绑）；控制台：多行回复卡片、单行复制、已发送/没发 outcome 按钮 |

**端口/地址默认值**：`AppConfig.default.serverURL = https://chat.anamne.top`（HTTPS，无需 ATS 例外）。

---

## 3. 好友绑定模型（复刻 PC 端，重要）

后端 generate 需要 **friend_id**，而 iOS 从屏幕只拿得到**会话名**。解析顺序与 PC 端 `app/settings.py: backend_friend()` 完全一致：

1. **绑定表**：`AppConfig.friendBindings[会话名]`（设置页里手动绑）
2. **自动匹配**：好友列表里 `nickname` 或 `remark` 与会话名**精确相等** → 自动记住绑定
3. **都没有 → 不生成**，通知提示「还没绑定后端好友」

**绝不拿 OCR 会话名自动建档**——PC 端的教训：会话名是 OCR 出来的字符串，抖一个字就是另一个人，自动建档等于批量制造垃圾档案。新建档案只能是用户在设置页点「用会话名新建档案并绑定」。

---

## 4. 配置怎么到扩展手里（免费/付费账号）

录屏扩展是独立进程，读配置的三条通道按优先级：

1. **App Group**（`group.allenfeng1.wechatocr`，付费开发者账号）——主 App 保存即生效
2. **命名剪贴板**（`wechatocr.config.v1`）——主 App 每次保存都写一份；免费账号也能用
3. **代码默认值** `AppConfig.default`——token 为空时扩展发通知「请先登录」，不死循环

免费账号模式下扩展**写不进** App Group 的控制台数据，所以扩展同时把新回复写进命名剪贴板 `wechatocr.config.v1.reply`，主 App 轮询时读取合并（2 秒轮询）。

---

## 5. 使用流程（对照 PC 端）

1. **设置页**：确认服务器地址 `https://chat.anamne.top` → 点「测试连接」→ 填用户名密码 → 「登录并保存」→ 「刷新列表」拉到好友档案
2. **绑定会话**：先在微信里打开目标聊天（让扩展识别一次），或直接在设置页「会话绑定」区填；下拉选好友档案（或「用会话名新建档案并绑定」）
3. **保存配置** → 结束并重新开始录屏广播
4. 微信聊天界面 → 控制中心长按录屏 → 选「WeChatOCR 采集」→ 开始直播
5. 对方来消息 → 通知「回复已就绪」（已复制到剪贴板）→ 打开微信长按输入框粘贴 → 分行的逐条发
6. 回控制台点「已发送 / 没发」→ 回传后端 outcome，历史记录保持准确

---

## 6. 防封号设计（与 PC 端视觉方案一致）

- 纯 OCR 视觉路线：不 hook、不注入、不走协议，微信眼里就是「一个在用手机的人」
- 客户端节流：默认最小间隔 5 秒 + 内容签名去重（同一条消息只生成一次）
- 后端侧风控由 MiraMate 自己管（PC 端同款链路）
- **发送永远由人手动完成**——剪贴板 + 通知，最后一下是人点的
- 回复内容 = 桃桃人设（后端 prompt），天然低重复率

---

## 7. 排错

| 现象 | 原因 / 解法 |
|---|---|
| 通知「未登录后端」 | 设置页没登录，或扩展走的是默认配置（免费模式检查命名剪贴板是否写成功：主 App 每次保存都会写） |
| 通知「还没绑定后端好友」 | 设置页 → 会话绑定 → 给这个会话选一个档案；或确认后端有同名 nickname/remark 的档案（自动匹配） |
| 「登录失败：用户名或密码错误」 | 后端 401 `{"detail":...}`，账号密码不对 |
| 「登录状态失效（401）」 | token 过期，重新登录 |
| 「后端没有这个好友档案（404）」 | 档案被删了，重新绑 |
| 有通知但回复是空的 | 后端返回 error（禁句被丢弃/模型没生成）——通知正文里带了原因；**不要重试同一内容**（有副作用） |
| 识别不到对方消息 | 微信字体太小/深色模式；气泡颜色判定阈值在 `OCRPipeline.classify()` |
| 群里不灵 | v1 面向单聊：群内发言人名（灰字）会被跳过，消息能收到但 @ 指定回复暂不支持 |

---

## 8. 与原参考服务器（server/）的关系

`server/` 目录里的 FastAPI 参考实现（`/api/v1/analyze`）**已废弃**，仅作历史参考。
真实后端是 MiraMate；如需改契约，只动 `Broadcast/APIClient.swift` 一个文件。
