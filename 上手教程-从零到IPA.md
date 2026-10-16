# 上手教程：从零到 IPA 装进 iPhone（Windows 用户版）

> 目标读者：**没有 Mac、用 Windows**，想把这个 App 装进自己 iPhone 跑起来的人。
> 全程免费，预计 1-2 小时（大部分时间在等构建和下载）。
>
> **总路径**：推代码到 GitHub → 云端自动构建出 IPA → Windows 装 AltStore → IPA 签名装进 iPhone → 配置后端地址 → 开微信试用。

---

## 目录

- 第 0 步：准备 3 样东西
- 第 1 步：把代码推到 GitHub
- 第 2 步：云端构建出 IPA
- 第 3 步：Windows 安装 AltStore 并装进 iPhone
- 第 4 步：把 IPA 装进 iPhone
- 第 5 步：配置你的后端地址（免费账号模式必做）
- 第 6 步：日常使用流程
- 第 7 步：7 天到期后续期
- 第 8 步：对接你自己的后端
- 附：常见问题排错

---

## 第 0 步：准备 3 样东西

| 东西 | 说明 |
|---|---|
| ① GitHub 账号 | https://github.com 注册，免费 |
| ② Git 工具 | 推荐下载 **GitHub Desktop**（图形界面，不用记命令）：https://desktop.github.com |
| ③ iPhone + 数据线 | iOS 16 以上，一根能连电脑的数据线 |

> 如果你熟悉命令行，也可以只用 Git for Windows，第 1 步有对应命令。

---

## 第 1 步：把代码推到 GitHub

### 方式 A：GitHub Desktop（推荐，全程点鼠标）

1. 打开 GitHub Desktop → 左上角 **File → Add local repository**（添加本地仓库）
2. 选择本项目的根目录：
   ```
   D:\workBuddyY\2026-10-17-06-13-42\wechat-ocr-autoreply
   ```
   如果提示"这不是一个 Git 仓库"，点 **create a repository**（创建仓库）后重试；创建时名字随便起（如 `wechat-ocr-autoreply`），**Git Ignore 选 None**（工程里已有自己的 .gitignore 需求，用 None 最稳）
3. 左下角填 Summary（提交说明），比如 `first commit`，点 **Commit to main**
4. 点顶部 **Publish repository**（发布仓库）→ 弹出的选项里：
   - **取消勾选 "Keep this code private"**（公开仓库 Actions 免费额度无限；私有仓库每月 2000 分钟也够用，但公开最省心）
   - 点 **Publish repository**
5. 等几秒，仓库就上传到 GitHub 了

### 方式 B：命令行（Git for Windows）

```bash
cd /d/workBuddyY/2026-10-17-06-13-42/wechat-ocr-autoreply
git init
git add .
git commit -m "first commit"
git branch -M main
git remote add origin https://github.com/你的用户名/仓库名.git
git push -u origin main
```

> ⚠️ **注意**：推上去就会自动触发一次构建（因为 workflow 监听 push）。免费 Apple ID 用户这次构建出来的 IPA **装不上**（缺 App Group 配置），没关系，第 2 步会教你怎么手动触发一次正确的构建，下载那次的产物就行。

---

## 第 2 步：云端构建出 IPA

1. 浏览器打开你的仓库页面，点顶部标签栏的 **Actions**
   - 如果提示"Workflows are not enabled"，点 **I understand, enable them**
2. 左侧列表点 **build-ipa** → 右侧出现 **Run workflow** 下拉按钮：
   - Branch 选 `main`
   - **如果你是免费 Apple ID 用户（绝大多数人）**：勾选 `free_account: true`
     （免费账号不能用 App Group，勾了这个会改用 `project.freeaccount.yml` 无 App Group 配置生成工程，否则签名/构建会出问题）
   - 如果你有 $99/年 付费开发者账号：保持不勾选，完整功能
3. 点绿色 **Run workflow** 按钮，页面刷新后会出现一个正在跑的任务（黄圈 = 构建中）
4. **等待 5-15 分钟**（GitHub 的 macOS 构建机要装 XcodeGen、编译两个 target）
5. 任务变绿勾 ✅ 后，点进这个任务 → 页面下方 **Artifacts** 区域 → 下载 **`WeChatOCRAutoReply-unsigned-ipa`**
   - 下载得到的是一个 zip，解压后里面的 `WeChatOCRAutoReply-unsigned.ipa` 就是我们要的安装包

> 💡 **构建失败了？** 点进任务看红色步骤的日志，把日志贴给我，我来修。常见失败原因：Bundle ID 撞名（改 `ios/project.yml` 里的 `bundleIdPrefix`）、免费账号没勾 `free_account`。

---

## 第 3 步：Windows 安装 AltStore 并装进 iPhone

AltStore 的作用：**用你的免费 Apple ID 给 IPA 签名，实现 7 天有效期的"自签名安装"**，不需要越狱、不需要付费账号。

### 3.1 安装 AltServer（Windows 端）

1. 到 https://altstore.io/ 下载 **AltServer for Windows**
2. **前置依赖**（装不上大概率是缺这个）：AltServer 依赖 **非 Microsoft Store 版的 iCloud**：
   - 从 Apple 官网下载 iCloud for Windows 安装包（不是应用商店里那个）
   - 装完后重启电脑
3. 运行 `AltServer.exe`，屏幕右下角任务栏会出现一个小图标

### 3.2 把 AltStore 装进 iPhone

1. **iPhone 数据线连接这台 Windows 电脑**，解锁屏幕，弹出"信任此电脑"时点**信任**
2. 点任务栏 AltServer 小图标 → **Install AltStore → 选择你的 iPhone**
3. 输入你的 **Apple ID 和密码**：
   - 开了双重认证的账号，密码要去 https://appleid.apple.com → 登录 → "App 专用密码" → 生成一个 16 位密码粘贴进去（普通密码会报错）
4. 等 1-2 分钟，iPhone 桌面上出现 **AltStore** 图标
5. iPhone 上首次打开 AltStore 前，先到 **设置 → 通用 → VPN与设备管理**，点你的 Apple ID → **信任**
6. 打开 AltStore，看到"我的应用"页面就成功了

> ⚠️ Apple ID 密码是本地直接发给苹果服务器签名的，AltStore 是开源软件（GitHub 可查源码），社区用了很多年；不放心可以专门注册一个新 Apple ID 只用来自签名。

---

## 第 4 步：把 IPA 装进 iPhone

1. 把第 2 步下载的 IPA 传到 iPhone，任选一种方式：
   - 微信"文件传输助手"发给自己，在 iPhone 微信里点开 → 右上角 `…` → 用其他应用打开 → 存到**"文件"App**
   - 或者数据线拷贝、或者 QQ、或者邮件
2. iPhone 打开 **AltStore → 我的应用 → 左上角 `+`**
3. 找到刚才存的 `WeChatOCRAutoReply-unsigned.ipa`，选中
4. 等安装完成，桌面出现 **WeChatOCR** 图标
5. 同样到 **设置 → 通用 → VPN与设备管理** 里**信任**这个开发者证书（免费证书每次安装后都要信任一次）

> 📌 **免费账号限制**：免费 Apple ID 同时最多装 3 个自签名 App（微信本体的正式 App 不算）。如果 AltStore 报 "app id limit"，删掉一个不常用的自签名 App 再装。

---

## 第 5 步：配置你的后端地址（免费账号模式必做）

免费账号模式下扩展读不到主 App 的设置页，服务器地址写在代码默认值里。你有两个选择：

### 选择 1：先用自带的参考服务器验证链路（推荐先做）

工程里有一个 FastAPI 参考服务器（`server/` 目录），可以跑在你自己的 Windows 电脑上：

```bash
# 在 D:\workBuddyY\2026-10-17-06-13-42\wechat-ocr-autoreply\server 目录下
# 用已装好依赖的 Python（venv 已就绪）：
C:\Users\Administrator\.workbuddy\binaries\python\envs\default\Scripts\python.exe main.py
```

启动后默认监听 `0.0.0.0:8000`。`LLM_API_KEY` 留空时自动用内置 Mock 回复（固定话术），足够验证"OCR → 上传 → 回复"整条链路。

### 选择 2：直接对接你自己的后端

打开文件：

```
ios/WeChatOCRAutoReply/Shared/SharedTypes.swift
```

找到第 21-24 行的 `AppConfig.default`，改成你的后端：

```swift
public static let `default` = AppConfig(
    serverURL: "http://192.168.1.50:8000",   // ← 改成你服务器的局域网 IP:端口
    apiToken: "",                            // ← 你的后端要 token 就填
    analyzePath: "/api/v1/analyze",          // ← 你的接口路径
    whitelist: [],
    enabled: true,
    minIntervalSeconds: 5,
    deviceId: UUID().uuidString
)
```

> ⚠️ **不要填 `localhost` 或 `127.0.0.1`** —— iPhone 访问不到你电脑的 localhost，必须填**局域网 IP**（Windows 上 `ipconfig` 查看，通常是 192.168.x.x）。同时确认 iPhone 和服务器在**同一个 Wi-Fi**，且 Windows 防火墙允许 8000 端口（第一次启动服务器时 Windows 弹防火墙提示，勾"专用网络"允许）。

改完后推送代码，等 Actions 自动重新构建（约 10 分钟），重新下载 IPA 重装一遍（AltStore 里直接覆盖安装）。

> 💡 如果你有 $99/年 付费开发者账号，以上都不用改——App 里设置页直接填后端地址，实时生效。

---

## 第 6 步：日常使用流程

装好并配好地址后，每次这样用：

1. 打开 **WeChatOCR** 主 App 一次（首次运行授予通知权限）
2. 打开**微信**，进入要盯的**聊天界面**
3. 下拉**控制中心** → **长按录屏按钮**（左上角那个双圈按钮）→ 选 **WeChatOCR** → 点**开始直播**
   - 屏幕顶部出现红色状态条 = 正在采集
4. 对方发来新消息后（约 1 秒内）：
   - 录屏帧被截取 → 本机 Vision OCR 识别整屏文字 → 上传你的后端
   - 后端返回回复 → **自动写入剪贴板 + 弹一条本地通知**："回复已就绪"
5. 点通知（或回微信）→ **长按输入框 → 粘贴 → 发送**
   - 跨 App 粘贴时 iOS 会弹"允许粘贴"，点一下即可
6. 用完**必须关闭**：点顶部红色状态条 → 停止广播（挂着费电，而且风控上"长时间挂机"也不妥）

**防封号纪律（重要，见调研报告第七章）**：
- 只回白名单里的联系人，别群发、别自动加好友、别碰红包支付
- 一天回复别超过 50 条，间隔别低于 30 秒
- 最后一下"发送"必须是你自己点的——半自动不是妥协，是保命设计

---

## 第 7 步：7 天到期后续期

免费证书 **7 天过期**，过期后 App 打不开（数据不丢）。续期方法：

1. iPhone 和这台 Windows **连同一个 Wi-Fi**（或数据线连着）
2. 电脑上确保 AltServer 在运行，iPhone 打开 **AltStore**
3. AltStore 会自动检测，**"我的应用"里 WeChatOCR 旁出现"刷新"按钮**，点一下（或 AltStore 首页下拉刷新）
4. 等 10-30 秒，有效期又续满 7 天

> 到期前 1-2 天 AltStore 会发本地通知提醒。如果换了网络环境导致刷新失败，就用数据线连一次电脑刷新。

---

## 第 8 步：对接你自己的后端

iOS 端和后端的所有交互都收敛在**一个文件**里：

```
ios/WeChatOCRAutoReply/Broadcast/APIClient.swift
```

**当前默认契约**：

```
POST {serverURL}{analyzePath}
Header: Content-Type: application/json
        Authorization: Bearer {apiToken}   （token 为空时不带）

请求体：
{
  "device_id":   "设备 UUID",
  "session":     "会话名 或 null",
  "screen_text": "OCR 识别出的整屏文本",
  "captured_at": "ISO8601 时间"
}

响应体：
{
  "action": "reply" | "ignore",
  "reply":  "回复文本（ignore 时为 null）",
  "reason": "可选，忽略原因"
}
```

解析是**宽松模式**：回复字段会依次尝试 `reply / text / message / content`，没有 `action` 字段但有回复文本时按 reply 处理——大部分常见接口不用改代码就能通。

**如果你的后端契约不同**，两种处理方式：

1. **差异小**（字段名不同、路径不同）：自己改 `APIClient.swift` 里请求体组装和 `AnalyzeResponseBody` 的解析
2. **差异大**（嵌套结构、非 REST、要签名等）：把接口地址、请求字段、返回示例贴给我，我直接帮你改好，你推上去重新构建

---

## 附：常见问题排错

| 现象 | 原因 / 解法 |
|---|---|
| Actions 显示 **"No workflows found"** | workflow 文件放错了位置——GitHub 只读仓库**根目录**的 `.github/workflows/`，已修复（文件必须在 `wechat-ocr-autoreply/.github/workflows/build-ipa.yml`，不在 `ios/` 里）。若你的仓库还是旧结构，把 `ios/.github` 整个删掉、确认根目录有 `.github/workflows/build-ipa.yml` 再推一次 |
| Actions 构建红叉 | 点进日志看哪步红的。大概率：①免费账号没勾 `free_account` → 重新 Run workflow 勾上；②Bundle ID 撞名 → 改 `ios/project.yml` 的 `bundleIdPrefix` |
| AltServer 装 AltStore 时报错 | 缺 Apple 官网版 iCloud for Windows（不是应用商店版）；或 Apple ID 开了双重认证要用 App 专用密码 |
| 装好 IPA 打不开 | 去 设置→通用→VPN与设备管理 信任证书（免费证书每次重装都要重新信任） |
| 提示"无法验证 App" | 证书过期，AltStore 里刷新；或重新装一次 |
| 录屏列表里没有 WeChatOCR | 扩展没装成功/没被系统识别。重装 IPA，装完先打开一次主 App |
| 采集了但没有回复通知 | ①iPhone 和服务器不在同一网段；②填了 localhost；③Windows 防火墙拦了端口；④后端没起。先在 iPhone Safari 直接访问 `http://你的IP:8000` 看通不通 |
| OCR 识别不准 | 微信字体调大一点、避免深色模式；识别级别在 `OCRPipeline.swift` 里已用 `.accurate` 最高精度 |
| 粘贴时弹"允许粘贴" | 系统正常行为，点允许即可，不影响安全 |
| 扩展很快被杀没反应 | 扩展内存上限约 50MB，工程已按 1 秒/帧节流；别在微信里开其他重负载功能 |
| 换 Apple ID / 换电脑 | AltStore 里先卸载 WeChatOCR，再用新环境重装，避免签名冲突 |

---

## 一页速查（收藏这段就够）

```
1. GitHub Desktop → Add 仓库 → Commit → Publish（取消 private 勾选）
2. 仓库 Actions → build-ipa → Run workflow → 勾 free_account=true → 等绿勾 → 下载 artifact
3. Windows 装 AltServer（先装 Apple 官网版 iCloud）→ iPhone 插线 → 任务栏 Install AltStore → 输 Apple ID（2FA 用 App 专用密码）
4. IPA 传到 iPhone（文件传输助手）→ AltStore 里点 + 安装 → 设置里信任证书
5. 改 SharedTypes.swift 的 serverURL 为你的局域网 IP → push → 等构建 → 重装
6. 微信聊天界面 → 控制中心长按录屏 → 选 WeChatOCR → 开始直播
7. 对方来消息 → 通知"回复已就绪" → 长按输入框粘贴发送
8. 每 7 天：iPhone 连同一 Wi-Fi → AltStore 一键刷新
```
