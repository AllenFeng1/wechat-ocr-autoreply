# ZXTouch v1.0.1（越狱触摸服务）安装说明

> 用途：本项目的「自动发送」依赖手机上的 zxtouch 服务（监听 127.0.0.1:6000）。
> App 通过 TCP 协议指挥它完成「点输入框 → 逐字输入 → 点发送」。
> 版本 v1.0.1（2026-10-15 发布），支持 iOS 15–18。

## 一、选哪个文件（关键）

本目录有两个 deb，**装错会无法启动**，按你的越狱工具选：

| 你的越狱工具 | 装这个 |
|---|---|
| Dopamine / Dopamine 3（rootless） | `com.zjx.ioscontrol_1.0.1_rootless.deb` |
| NathanLR（rootless） | `com.zjx.ioscontrol_1.0.1_rootless.deb` |
| Roothide / Serotonin | `com.zjx.ioscontrol_1.0.1_roothide.deb` |

不确定用的哪个？看手机桌面：越狱工具叫 Dopamine 就选 rootless；叫 Serotonin 或提示
"roothide" 就选 roothide。传统 rootful 越狱（unc0ver/checkra1 系列，iOS 14 及以下）
用这个 fork 不支持，回去用原版 v0.0.7-10。

## 二、安装方式（二选一）

### 方式 A：Filza 文件管理器（推荐，不用电脑）

**0. 先装 Filza**（如果手机上还没有）：
1. 打开 **Sileo**（越狱工具自带，桌面上蓝白色图标）
2. 底部「搜索」→ 输入 `Filza`
3. 安装 **Filza File Manager 64-bit**（免费版即可，作者 TigiSoftware）
4. 搜不到或提示不兼容你的系统：Sileo → 更多 → 源管理 → 编辑 → 添加
   `https://tigisoftware.com/cydia/` → 刷新后再搜 Filza
   （iOS 15–18 的 rootless/roothide 越狱需要 Filza 3.8.9 以上版本）

**1. 传 deb 到手机**：微信文件传输助手 / QQ / AirDrop 均可

**2. 用 Filza 安装**：
1. Filza 里找到刚传进来的 deb（一般在「最近项目」或 `/var/mobile/Documents`）
2. 点一下这个 deb 文件 → 右上角 **「Install」**
3. 等进度条走完、SpringBoard 自动重启 → 桌面出现 **ZXTouch** App 图标即成功

### 方式 B：SSH + dpkg

```bash
# 把 deb 传到手机后（以 rootless 版为例）
scp com.zjx.ioscontrol_1.0.1_rootless.deb root@手机IP:/var/mobile/
ssh root@手机IP
dpkg -i /var/mobile/com.zjx.ioscontrol_1.0.1_rootless.deb
killall -9 SpringBoard
```

## 三、装好后验证（30 秒）

```bash
ssh root@手机IP
# rootless 越狱执行：
/var/jb/usr/bin/zxtouchd --version    # 或直接看进程
netstat -an | grep 6000               # 应看到 127.0.0.1:6000 在 LISTEN
```

更直接的验证：手机上打开 ZXTouch App，能看到主界面就说明服务正常。
我们的 App 里点「设置 → 测试连接」显示"zxtouch 服务可用"即全链路通。

## 四、依赖

- `mobilesubstrate | ellekit`：越狱工具自带，无需单独装
- `firmware >= 15.0`
- 我们的方案**不需要**在手机上装 Python（App 直接说 TCP 协议，不跑 .py 脚本）

## 五、和本项目 App 的对接点

- 端口：`127.0.0.1:6000`（App 内置，不可改）
- 协议：`<task>;;<param>\r\n`，本项目 `ZXTouchClient.swift` 已实现：
  - `touch`（task=10）：模拟点击
  - `switch_to_app`（task=11）：把微信带到前台
  - `kb insert_text`（task=24, sub=1）：逐字输入（不经输入法，中文安全）
- 安装即自动监听，**无需手动启动服务**；重启手机后越狱工具重新激活即可

## 来源

- 上游（原版，iOS ≤14）：https://github.com/xuan32546/IOS13-SimulateTouch
- 本 fork（rootless/roothide，iOS 15–18）：https://github.com/epic0001/zxtouchrootless
- 文件校验：
  - rootless.deb  md5 `552617cf3b4b3cb159da9dbb139fae2e`（1,033,660 字节）
  - roothide.deb md5 `f0904dd66fed5b4dbe2d353ad0fad6e6`（1,031,086 字节）
