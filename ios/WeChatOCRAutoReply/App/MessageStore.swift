import Foundation

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

        // 录屏扩展写入共享数据后，主 App 通过信号时间戳感知并刷新（2s 轮询，简单可靠）
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            let signal = SharedStore.changedSignal
            if signal != self.lastSignal {
                self.lastSignal = signal
                self.reload()
            }
        }
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
}
