import Foundation

/// App Group 共享容器：录屏扩展写消息/回复，主 App 读并展示。
/// 通过 UserDefaults 里的时间戳信号通知对方数据已变化。
public enum SharedStore {
    private static let messagesFile = "messages.json"
    private static let repliesFile = "replies.json"
    private static let signalKey = "shared_changed_at"

    public static func containerURL() -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: ConfigStore.appGroupSuite)
    }

    // MARK: 消息

    public static func saveMessages(_ messages: [RecognizedMessage]) {
        write(messages, to: messagesFile)
        notifyChanged()
    }

    public static func loadMessages() -> [RecognizedMessage] {
        read([RecognizedMessage].self, from: messagesFile) ?? []
    }

    // MARK: 回复

    public static func saveReplies(_ replies: [ReplySuggestion]) {
        write(replies, to: repliesFile)
        notifyChanged()
    }

    public static func loadReplies() -> [ReplySuggestion] {
        read([ReplySuggestion].self, from: repliesFile) ?? []
    }

    // MARK: 变更信号

    public static func notifyChanged() {
        ConfigStore.defaults.set(Date().timeIntervalSince1970, forKey: signalKey)
    }

    public static var changedSignal: Double {
        ConfigStore.defaults.double(forKey: signalKey)
    }

    // MARK: 私有

    private static func write<T: Encodable>(_ value: T, to fileName: String) {
        guard let dir = containerURL() else { return }
        let url = dir.appendingPathComponent(fileName)
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private static func read<T: Decodable>(_ type: T.Type, from fileName: String) -> T? {
        guard let dir = containerURL() else { return nil }
        let url = dir.appendingPathComponent(fileName)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
