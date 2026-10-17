import Foundation
import UIKit

private let diagTimeFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "HH:mm:ss"
    return f
}()

/// 主 App 的状态中枢：加载配置、轮询共享数据变化、提供操作。
final class MessageStore: ObservableObject {
    @Published var messages: [RecognizedMessage] = []
    @Published var replies: [ReplySuggestion] = []
    @Published var config: AppConfig = .default
    @Published var appGroupAvailable = SharedStore.isAvailable
    /// 后端好友列表（设置页下拉 & 控制台显示）
    @Published var friends: [FriendProfile] = []
    /// 登录/操作状态提示
    @Published var status: String = ""
    @Published var busy = false

    private var timer: Timer?
    private var lastSignal: Double = SharedStore.changedSignal

    init() {
        config = ConfigStore.shared.load()
        friends = ConfigStore.shared.cachedFriends()
        reload()

        // 自动发送阶段变化（引擎单例回调 → UI）
        AutoSendEngine.shared.onPhase = { [weak self] phase, message in
            self?.autoSendPhase = phase
            self?.autoSendMessage = message
            if phase == .done || phase == .failed {
                self?.autoSendRunning = false
            }
        }

        // 录屏扩展写入共享数据后，主 App 通过信号时间戳感知并刷新（2s 轮询，简单可靠）
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            let signal = SharedStore.changedSignal
            if signal != self.lastSignal {
                self.lastSignal = signal
                self.reload()
            }
            self.broadcastHB = BroadcastHeartbeatBus.latest()
            self.drainPendingSends()
        }
    }

    // MARK: - 录屏扩展生命周期探针（诊断页用）

    /// 扩展最近一次广播的探针数据；nil = 扩展从未写过（从没启动成功过）
    @Published var broadcastHB: BroadcastHeartbeat?

    /// 探针数据的人话解读（诊断页展示）
    var broadcastStatusLines: [String] {
        guard let hb = broadcastHB, let started = hb.startedAt else {
            return ["扩展从未启动成功过 —— 如果刚在控制中心选了「WeChatOCR」开始直播，" +
                    "大概率是扩展签名/权限问题（免费账号 IPA 需确认扩展被一起签名）",
                    "也可能是 setup 阶段崩溃：去 设置→隐私与安全性→分析与改进→分析数据，" +
                    "搜 Broadcast 看有没有崩溃报告"]
        }
        var lines: [String] = []
        lines.append("扩展启动于 \(diagTimeFormatter.string(from: started))")
        lines.append("已处理 \(hb.frames) 帧文字")
        if let last = hb.lastFrameAt {
            lines.append("最近识别到文字：\(diagTimeFormatter.string(from: last))")
        } else if hb.frames == 0 {
            lines.append("⚠️ 启动后一帧文字都没处理出来就停了 —— 典型的内存超限（50MB jetsam）" +
                         "或 mediaservicesd 被重置；可在分析数据里搜 Broadcast 确认")
        }
        if let fin = hb.finishedAt {
            lines.append("扩展自行结束于 \(diagTimeFormatter.string(from: fin))（正常停止）")
        } else {
            lines.append("⚠️ 没有正常结束记录 —— 这次是被系统杀掉的（你看到的" +
                         "「直播屏幕已停止」就是它）")
        }
        if !hb.lastError.isEmpty {
            lines.append("扩展侧最近错误：\(hb.lastError)")
        }
        return lines
    }

    // MARK: - 自动发送（越狱 + zxtouch）

    @Published var autoSendPhase: AutoSendEngine.Phase = .idle
    @Published var autoSendMessage = ""
    @Published var autoSendRunning = false

    /// 把排队里的待发送逐条交给引擎。引擎忙就等下一轮轮询（2s）。
    private func drainPendingSends() {
        guard config.autoSendEnabled, !autoSendRunning else { return }
        let pending = PendingSendBus.consume()
        guard let first = pending.first else { return }
        // 一次只发一条；没发完的留在队列里等下一轮
        if pending.count > 1 {
            PendingSendBus.post(contentsOf: pending.dropFirst())
        }
        autoSendRunning = true
        AutoSendEngine.shared.onPhase = { [weak self] phase, message in
            self?.autoSendPhase = phase
            self?.autoSendMessage = message
            if phase == .done || phase == .failed {
                self?.autoSendRunning = false
                if phase == .done {
                    self?.reportAutoSent(session: first.session, friendId: first.friendId)
                } else {
                    // 失败兜底：通知用户手动粘贴（剪贴板里已有回复内容）
                    self?.status = "自动发送失败：\(message)（回复已在剪贴板，可手动粘贴）"
                }
            }
        }
        let ok = AutoSendEngine.shared.start(
            AutoSendEngine.PendingSend(session: first.session, reply: first.reply,
                                       friendId: first.friendId),
            config: config)
        if !ok {
            autoSendRunning = false
            if pending.count > 1 {
                PendingSendBus.post(contentsOf: pending.dropFirst())
            }
        }
    }

    /// 自动发送成功：回传 outcome=sent 给后端（与手动发送同语义）
    private func reportAutoSent(session: String, friendId: Int) {
        let suggestion = ReplySuggestion(session: session, friendId: friendId,
                                         reply: "", outcome: "sent")
        reportOutcome(suggestion, action: "sent")
    }

    /// 设置页「测试连接」：连一下 zxtouch 服务通不通，失败时带上可操作的原因
    func testTouchService(completion: @escaping (Bool, String) -> Void) {
        ZXTouchClient.shared.connect { ok, msg in
            completion(ok, msg)
        }
    }

    /// 保存校准坐标（校准页调用）
    func saveTouchPoints(_ points: TouchPoints) {
        config.touchPoints = points
        saveConfig()
    }

    func reload() {
        messages = SharedStore.loadMessages()
        replies = SharedStore.loadReplies()
    }

    func saveConfig() {
        ConfigStore.shared.save(config)
        config = ConfigStore.shared.load()
        appGroupAvailable = SharedStore.isAvailable
    }

    // MARK: - 后端操作

    /// 设置页「测试连接」：health 不需要鉴权
    func testConnection() {
        let problem = BackendClient.healthCheck(base: config.serverURL)
        status = problem.map { "连不上：\($0)" } ?? "连接正常（\(config.normalizedServerURL)）"
    }

    /// 登录：成功后把 token 写回配置（扩展随后能拿到）
    func login() {
        let username = config.username.trimmingCharacters(in: .whitespaces)
        let password = config.password
        guard !username.isEmpty, !password.isEmpty else {
            status = "先填用户名和密码"
            return
        }
        busy = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            do {
                let token = try BackendClient(base: self.config.normalizedServerURL)
                    .login(username: username, password: password)
                DispatchQueue.main.async {
                    self.config.apiToken = token
                    self.saveConfig()
                    self.status = "登录成功"
                    self.busy = false
                    self.refreshFriends()
                }
            } catch let e as BackendError {
                DispatchQueue.main.async {
                    self.status = "登录失败：\(e.message)"
                    self.busy = false
                }
            } catch {
                DispatchQueue.main.async {
                    self.status = "登录失败：\(error.localizedDescription)"
                    self.busy = false
                }
            }
        }
    }

    func refreshFriends() {
        guard !config.apiToken.isEmpty else {
            status = "还没登录，先登录再拉好友列表"
            return
        }
        busy = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            do {
                let list = try BackendClient(base: self.config.normalizedServerURL,
                                             token: self.config.apiToken).listFriends()
                DispatchQueue.main.async {
                    self.friends = list
                    ConfigStore.shared.cacheFriends(list)
                    self.status = "好友列表已更新（\(list.count) 个）"
                    self.busy = false
                }
            } catch let e as BackendError {
                DispatchQueue.main.async {
                    self.status = "拉好友失败：\(e.message)"
                    self.busy = false
                }
            } catch {
                DispatchQueue.main.async {
                    self.status = "拉好友失败：\(error.localizedDescription)"
                    self.busy = false
                }
            }
        }
    }

    /// 用当前会话名新建一个空档案并绑定（PC 端「新建」的同等行为，仅用户显式触发）
    func createAndBind(session: String) {
        guard !config.apiToken.isEmpty else { status = "还没登录"; return }
        let name = session.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { status = "会话名是空的"; return }
        busy = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            do {
                let id = try BackendClient(base: self.config.normalizedServerURL,
                                           token: self.config.apiToken)
                    .createFriend(nickname: name)
                DispatchQueue.main.async {
                    _ = ConfigStore.shared.bind(session: name, friendId: id)
                    self.config = ConfigStore.shared.load()
                    self.status = "已建档并绑定「\(name)」→ #\(id)"
                    self.busy = false
                    self.refreshFriends()
                }
            } catch let e as BackendError {
                DispatchQueue.main.async {
                    self.status = "建档失败：\(e.message)"
                    self.busy = false
                }
            } catch {
                DispatchQueue.main.async {
                    self.status = "建档失败：\(error.localizedDescription)"
                    self.busy = false
                }
            }
        }
    }

    func bind(session: String, friendId: Int) {
        _ = ConfigStore.shared.bind(session: session, friendId: friendId)
        config = ConfigStore.shared.load()
    }

    func unbind(session: String) {
        _ = ConfigStore.shared.unbind(session: session)
        config = ConfigStore.shared.load()
    }

    // MARK: - 回复卡片操作

    func markCopied(_ reply: ReplySuggestion) {
        var all = SharedStore.loadReplies()
        if let index = all.firstIndex(where: { $0.id == reply.id }) {
            all[index].copied = true
            SharedStore.saveReplies(all)
        }
        reload()
    }

    /// 用户实际处理结果回传后端（sent / edited / cancelled）
    func reportOutcome(_ reply: ReplySuggestion, action: String, finalText: String = "") {
        guard reply.friendId > 0, !config.apiToken.isEmpty else { return }
        var all = SharedStore.loadReplies()
        if let index = all.firstIndex(where: { $0.id == reply.id }) {
            all[index].outcome = action
            SharedStore.saveReplies(all)
        }
        reload()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            try? BackendClient(base: self.config.normalizedServerURL,
                               token: self.config.apiToken)
                .reportOutcome(friendId: reply.friendId, action: action, finalText: finalText)
        }
    }

    func clearHistory() {
        SharedStore.saveMessages([])
        SharedStore.saveReplies([])
        reload()
    }

    // MARK: - 诊断（不开录屏，直接验证 OCR 解析 + 后端生成）

    @Published var diagLines: [ParsedLine] = []
    @Published var diagSession = ""
    @Published var diagIncoming = ""
    @Published var diagReply = ""
    @Published var diagNote = ""
    @Published var diagBusy = false
    @Published var diagLog: [String] = []

    func diagLogAdd(_ s: String) {
        let line = "[\(diagTimeFormatter.string(from: Date()))] \(s)"
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.diagLog.insert(line, at: 0)
            if self.diagLog.count > 100 { self.diagLog.removeLast() }
        }
    }

    /// 拿一张微信聊天截图跑完整条 OCR 解析（会话名 + 她/我分类 + incoming 提取）
    func diagTestImage(_ image: UIImage) {
        diagLogAdd("开始解析截图（\(Int(image.size.width))×\(Int(image.size.height))）")
        guard let cg = image.cgImage else {
            diagLogAdd("取不到图片数据，换一张截图")
            return
        }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let pipeline = OCRPipeline()
            guard let r = pipeline.parse(image: cg) else {
                self.diagLogAdd("OCR 没识别出文字：换一张更清晰的聊天截图")
                return
            }
            let counts = Dictionary(grouping: r.lines, by: { $0.kind }).mapValues { $0.count }
            DispatchQueue.main.async {
                self.diagLines = r.lines
                self.diagSession = r.session
                self.diagIncoming = r.incomingFromHer
                self.diagLogAdd("解析完成：她=\(counts[.her] ?? 0) 我=\(counts[.me] ?? 0) 灰=\(counts[.gray] ?? 0) 图=\(counts[.image] ?? 0)")
                if r.session.isEmpty { self.diagLogAdd("⚠️ 会话名没识别到，可手动填（要和微信顶部一致）") }
                if r.incomingFromHer.isEmpty { self.diagLogAdd("⚠️ 没提取到对方消息：确认截图里对方气泡在最底部几行") }
            }
        }
    }

    /// 用诊断页里的 会话名 + 对方消息 直接调后端生成（和录屏链路同一套代码）
    func diagGenerate() {
        guard !config.apiToken.isEmpty else {
            diagLogAdd("还没登录：先去「设置」页登录 AnamneChat 并保存")
            return
        }
        let session = diagSession.trimmingCharacters(in: .whitespacesAndNewlines)
        let incoming = diagIncoming.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !session.isEmpty else { diagLogAdd("会话名是空的，先填一个"); return }
        guard !incoming.isEmpty else { diagLogAdd("对方消息是空的，先填上要测试的内容"); return }

        let friends = ConfigStore.shared.cachedFriends()
        let fid = ConfigStore.shared.resolveFriendId(session: session, friends: friends)
        guard fid > 0 else {
            diagLogAdd("「\(session)」没绑定好友：去「设置 → 会话绑定」绑定，或用会话名新建档案")
            return
        }
        diagBusy = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            do {
                let r = try BackendClient(base: self.config.normalizedServerURL,
                                          token: self.config.apiToken)
                    .generate(friendId: fid, incoming: incoming)
                DispatchQueue.main.async {
                    self.diagReply = r.reply
                    self.diagNote = r.note
                    self.diagBusy = false
                    self.diagLogAdd("✅ 生成成功（friend #\(fid)）")
                }
            } catch let e as BackendError {
                DispatchQueue.main.async {
                    self.diagBusy = false
                    self.diagLogAdd("❌ 生成失败：\(e.message)")
                }
            } catch {
                DispatchQueue.main.async {
                    self.diagBusy = false
                    self.diagLogAdd("❌ 失败：\(error.localizedDescription)")
                }
            }
        }
    }

    func diagClear() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.diagLines = []
            self.diagSession = ""
            self.diagIncoming = ""
            self.diagReply = ""
            self.diagNote = ""
            self.diagLog = []
        }
    }
}
