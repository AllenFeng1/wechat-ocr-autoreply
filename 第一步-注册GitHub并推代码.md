# 第一步拆解：注册 GitHub + 推代码（超详细版）

> 适合：**没有 GitHub 账户、第一次用 Git** 的 Windows 用户。
> 预计 20-30 分钟。每步末尾都有 ✅ **完成标志**，对不上就说明哪步做错了。
>
> 这一步的目标只有一个：把 `wechat-ocr-autoreply` 文件夹推到 GitHub 上，让后面的云构建能读到它。

---

## 1.1 注册 GitHub 账户（10 分钟）

1. 浏览器打开 **https://github.com**，点右上角绿色按钮 **Sign up**
2. 页面分三步，逐页填：
   - **Enter your email**：填你的常用邮箱（QQ 邮箱、163、Gmail 都行）
   - **Create a password**：设一个密码（记住它，后面登录要用）
   - **Enter a username**：想一个用户名。要求：只能含字母、数字、连字符，**不能与别人重名**。比如 `zhangsan-wechat` 这种。被占用就换一个
3. 点 **Continue** 后可能会出一个人机验证（拼图或图片选择），按提示过
4. 接下来 GitHub 会问你几个偏好问题（团队规模、用途、是否学生等）——**全部跳过**：页面最下方有 **Skip** 按钮，或者直接往下滚到底点 **Complete setup**
5. **验证邮箱**：GitHub 会往你填的邮箱发一封邮件，里面有一串数字验证码（形如 `12345678`）。登录邮箱复制，回到 GitHub 页面粘贴进去
   - 收件箱没有？**看垃圾邮件/广告邮件文件夹**，这是最常见的卡点
6. 验证通过后进入你的 GitHub 主页，左上角能看到你的头像

✅ **完成标志**：浏览器地址栏在 `github.com`，页面右上角显示你的头像，且邮箱已验证（没有黄条提示 "Please verify your email"）。

---

## 1.2 下载安装 GitHub Desktop（5 分钟）

GitHub Desktop 是图形界面工具，**全程点鼠标，不用记任何命令**。

1. 打开 **https://desktop.github.com**，页面会自动开始下载 `GitHubDesktopSetup.exe`（约 100MB）
2. 双击下载好的安装包，一路 **Next / Install**，装完自动打开
3. 第一次打开会出现欢迎页，点中间的 **Sign in to GitHub.com**（不是 "Sign in to GitHub Enterprise"）
4. 浏览器会自动弹出 GitHub 授权页面：
   - 如果没登录 GitHub，先输刚注册的账号密码登录
   - 授权页点绿色按钮 **Authorize desktop**
5. 浏览器提示"可以返回 GitHub Desktop 了"，关掉浏览器回到 Desktop
6. Desktop 界面可能让你配置 Git 身份（Name / Email）—— **Name 填你的用户名，Email 填注册 GitHub 用的邮箱**，点 **Finish**

✅ **完成标志**：GitHub Desktop 主界面打开，右上角（或菜单里）显示你的 GitHub 头像/用户名，没有要求登录的提示。

---

## 1.3 把项目文件夹推上 GitHub（10 分钟）

这一步的对象是本项目的文件夹：

```
D:\workBuddyY\2026-10-17-06-13-42\wechat-ocr-autoreply
```

> 💡 路径确认方法：打开"此电脑" → D 盘 → 逐层点进 `workBuddyY → 2026-10-17-06-13-42 → wechat-ocr-autoreply`，能看到里面有 `README.md`、`ios`、`server` 三个东西就对了。

### 步骤 A：添加本地文件夹

1. GitHub Desktop 左上角菜单 **File → Add local repository**（中文界面：文件 → 添加本地仓库）
2. 弹窗里点 **Choose...**（选择）按钮，按上面的路径找到 `wechat-ocr-autoreply` 文件夹，选中，点"选择文件夹"
3. 点 **Add repository**（添加）

### 步骤 B：如果提示"不是 Git 仓库"

大概率会弹一个错误：**"This directory does not appear to be a Git repository"**（该目录不是 Git 仓库）。**这是正常的**，按下面做：

1. 同一个弹窗里有个蓝色链接 **create a repository**（创建仓库），点它
2. 填两个空：
   - **Name**：仓库名，填 `wechat-ocr-autoreply`
   - **Git ignore**：保持 **None**（不要选，工程本身已处理好）
   - **License**：不用管
3. 点 **Create repository**（创建仓库）

### 步骤 C：提交（Commit）

1. 添加成功后，Desktop 主界面中间会列出大量文件（`ios/...`、`server/...`、`README.md` 等），**全部保持勾选**
2. 左下角 **Summary**（摘要）输入框里填：`first commit`
3. 点蓝色按钮 **Commit to main**（提交到 main）

### 步骤 D：发布（Publish）到 GitHub

1. 点顶部工具栏的 **Publish repository**（发布仓库）按钮
2. 弹窗里只有一项要改：
   - **☐ Keep this code private** —— 这个勾选框：
     - **建议取消勾选（公开仓库）**：Actions 云构建免费额度无限，随便用
     - **想保密就勾上（私有仓库）**：每月也有 2000 分钟免费构建额度，跑一次约 10 分钟，个人用绰绰有余
   - 两种都行，随你
3. 点 **Publish repository**

✅ **完成标志**：
- Desktop 界面顶部工具栏按钮从 "Publish repository" 变成 **"Fetch origin"**，且中间的文件列表变空（说明已全部推上去）
- 浏览器打开 `https://github.com/你的用户名/wechat-ocr-autoreply`，能看到项目文件列表（`ios`、`server`、`README.md`）

两个标志都对上 = 第一步完成，可以进行下一步（云构建）。

---

## 1.4 推完之后会发生什么

代码推上去的瞬间，GitHub 会**自动开始第一次构建**（这是工程里预设的 `.github/workflows/build-ipa.yml` 在工作）。

- 打开仓库页面 → 顶部 **Actions** 标签 → 能看到一个叫 `build-ipa` 的任务在跑（黄圈）
- ⚠️ **这次自动构建的 IPA 先别用**：它默认走付费账号配置，免费 Apple ID 装不上。以它为准没关系，下一步会教你**手动再触发一次正确配置的构建**，下载那次的产物
- 这次自动构建失败（红叉）也不用慌，原因同上

---

## 1.5 排错

| 现象 | 解法 |
|---|---|
| 注册时验证邮件收不到 | 看垃圾邮件文件夹；QQ 邮箱可能在"自助查询"里；等 2 分钟刷新。还不行就换个邮箱注册 |
| 人机验证过不去 | 刷新页面重来；换 Chrome/Edge 浏览器试试 |
| Add local repository 找不到文件夹 | 确认路径是 `D:\workBuddyY\2026-10-17-06-13-42\wechat-ocr-autoreply`，一层层找，别手打路径 |
| 装 GitHub Desktop 后打不开/闪退 | 重启电脑；确认系统是 Windows 10 或 11 |
| Sign in 时浏览器没反应 | Desktop 里重新点一次 Sign in；或浏览器手动打开 github.com 登录后，再回 Desktop 点 |
| Publish 后仓库页面 404 | 地址里的用户名拼错了；或仓库是私有的，未登录时看不到——先登录 GitHub 再看 |
| 误勾了 Keep this code private 想改公开 | 仓库页面 → Settings → 最下方 Danger Zone → Change visibility → Public |

---

## 下一步

第一步完成后，回到主教程《上手教程-从零到IPA.md》的**第 2 步：云端构建出 IPA**——那里会教你勾选 `free_account=true` 重新构建，下载能装进 iPhone 的 IPA。
