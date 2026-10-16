import Foundation

/// 主 App 的状态中枢：加载配置、轮询共享数据变化、提供操作。
final class MessageStore: ObservableObject {
    @Published var messages: [RecognizedMessage] = []
    @Published var replies: [ReplySuggestion] = []
    @Published var config: AppConfig = .default
    @Published var appGroupAvailable = ConfigStore.isAppGroupAvailable

    private var timer: Timer?
    private var lastSignal: Double = SharedStore.changedSignal

    init() {
        config = ConfigStore.load()
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
        ConfigStore.save(config)
        config = ConfigStore.load()
        appGroupAvailable = ConfigStore.isAppGroupAvailable
    }

    func markCopied(_ reply: ReplySuggestion) {
        var all = SharedStore.loadReplies()
        if let index = all.firstIndex(where: { $0.id == reply.id }) {
            all[index].copied = true
            SharedStore.saveReplies(all)
        }
        reload()
    }

    func clearHistory() {
        SharedStore.saveMessages([])
        SharedStore.saveReplies([])
        reload()
    }
}
