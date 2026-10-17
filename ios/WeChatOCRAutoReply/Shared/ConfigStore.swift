import Foundation
import UIKit

/// 配置存储 + 会话绑定 + 好友缓存。
///
/// 扩展（录屏进程）读配置的三条通道，按优先级：
///   1. App Group 共享 UserDefaults（付费开发者账号；最稳）
///   2. 命名剪贴板 group.wechatocr.config（免费账号可用；主 App 每次保存都写一份）
///   3. AppConfig.default（代码默认值；免费模式下 token 为空 → 通知提示去主 App 登录）
public final class ConfigStore {
    public static let shared = ConfigStore()

    public let appGroupId = "group.allenfeng1.wechatocr"
    public let pasteboardName = "wechatocr.config.v1"

    private let configKey = "app_config.v2"
    private let messagesKey = "messages.v2"
    private let repliesKey = "replies.v2"
    private let friendsCacheKey = "friends_cache.v1"

    private var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroupId)
    }

    private init() {}

    // MARK: - 配置读写（主 App 侧）

    public func load() -> AppConfig {
        guard let data = defaults?.data(forKey: configKey),
              let cfg = try? JSONDecoder().decode(AppConfig.self, from: data) else {
            return .default
        }
        return cfg
    }

    public func save(_ cfg: AppConfig) {
        if let data = try? JSONEncoder().encode(cfg) {
            defaults?.set(data, forKey: configKey)
        }
        // 同步一份到命名剪贴板，供免费账号模式下的扩展读取
        if let data = try? JSONEncoder().encode(cfg) {
            UIPasteboard(name: UIPasteboard.Name(rawValue: pasteboardName), create: true)?.setData(
                data, forPasteboardType: "public.json")
        }
    }

    // MARK: - 配置读取（扩展侧：三层通道）

    public func loadForExtension() -> AppConfig {
        if let data = defaults?.data(forKey: configKey),
           let cfg = try? JSONDecoder().decode(AppConfig.self, from: data) {
            return cfg
        }
        if let pb = UIPasteboard(name: UIPasteboard.Name(rawValue: pasteboardName), create: false),
           let data = pb.data(forPasteboardType: "public.json"),
           let cfg = try? JSONDecoder().decode(AppConfig.self, from: data) {
            return cfg
        }
        return .default
    }

    // MARK: - 会话绑定（会话名 → friend_id）

    public func bindings() -> [String: Int] {
        load().friendBindings
    }

    @discardableResult
    public func bind(session: String, friendId: Int) -> AppConfig {
        var cfg = load()
        cfg.friendBindings[session] = friendId
        save(cfg)
        return cfg
    }

    @discardableResult
    public func unbind(session: String) -> AppConfig {
        var cfg = load()
        cfg.friendBindings.removeValue(forKey: session)
        save(cfg)
        return cfg
    }

    /// 解析会话对应的好友 id。顺序与 PC 端 app/settings.py backend_friend 一致：
    /// 绑定表 → 按昵称/备注自动匹配（匹配上就记住绑定）→ 0（未绑定，绝不自动建档）。
    public func resolveFriendId(session: String, friends: [FriendProfile]) -> Int {
        let key = session.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return 0 }
        if let hit = bindings()[key], hit > 0 { return hit }
        // 自动匹配：nickname / remark 精确相等
        if let auto = friends.first(where: {
            $0.nickname == key || ($0.remark == key && !key.isEmpty)
        }) {
            _ = bind(session: key, friendId: auto.id)
            return auto.id
        }
        return 0
    }

    // MARK: - 好友列表缓存（供设置页下拉 & 扩展自动匹配）

    public func cachedFriends() -> [FriendProfile] {
        guard let data = defaults?.data(forKey: friendsCacheKey),
              let list = try? JSONDecoder().decode([FriendProfile].self, from: data) else {
            return []
        }
        return list
    }

    public func cacheFriends(_ list: [FriendProfile]) {
        if let data = try? JSONEncoder().encode(list) {
            defaults?.set(data, forKey: friendsCacheKey)
        }
    }

    // MARK: - 消息流 / 回复卡片（主 App 与扩展共享，App Group 可用时）

    public func loadMessages() -> [RecognizedMessage] {
        guard let data = defaults?.data(forKey: messagesKey),
              let list = try? JSONDecoder().decode([RecognizedMessage].self, from: data) else {
            return []
        }
        return list
    }

    public func saveMessages(_ list: [RecognizedMessage]) {
        let trimmed = Array(list.suffix(100))
        if let data = try? JSONEncoder().encode(trimmed) {
            defaults?.set(data, forKey: messagesKey)
        }
    }

    public func loadReplies() -> [ReplySuggestion] {
        guard let data = defaults?.data(forKey: repliesKey),
              let list = try? JSONDecoder().decode([ReplySuggestion].self, from: data) else {
            return []
        }
        return list
    }

    public func saveReplies(_ list: [ReplySuggestion]) {
        let trimmed = Array(list.suffix(100))
        if let data = try? JSONEncoder().encode(trimmed) {
            defaults?.set(data, forKey: repliesKey)
        }
    }

    /// 免费模式下扩展写不进 App Group：用命名剪贴板把新回复递给主 App
    public func publishReplyViaPasteboard(_ reply: ReplySuggestion) {
        guard let data = try? JSONEncoder().encode(reply) else { return }
        UIPasteboard(name: UIPasteboard.Name(rawValue: pasteboardName + ".reply"), create: true)?
            .setData(data, forPasteboardType: "public.json")
    }
}
