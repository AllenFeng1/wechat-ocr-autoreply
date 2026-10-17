import Foundation
import UIKit

// =====================================================================
//  PendingSendItem / PendingSendBus：待自动发送的回复，跨进程传递
// =====================================================================
//  录屏扩展生成回复后，如果用户开了自动发送，就走这里递给主 App：
//    付费账号（App Group 可用）：SharedStore 文件 + UserDefaults 信号
//    免费账号：命名剪贴板 JSON（与 publishReplyViaPasteboard 同套路）
//  主 App 每 2s 轮询 consume()，喂给 AutoSendEngine。
// =====================================================================

public struct PendingSendItem: Codable, Equatable {
    public var id: String
    public var session: String
    public var reply: String
    public var friendId: Int
    public var createdAt: Date

    public init(session: String, reply: String, friendId: Int) {
        self.id = UUID().uuidString
        self.session = session
        self.reply = reply
        self.friendId = friendId
        self.createdAt = Date()
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        session = try c.decodeIfPresent(String.self, forKey: .session) ?? ""
        reply = try c.decodeIfPresent(String.self, forKey: .reply) ?? ""
        friendId = try c.decodeIfPresent(Int.self, forKey: .friendId) ?? 0
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    }
}

public enum PendingSendBus {
    private static let maxQueue = 5

    /// 扩展侧调用：入队一条待发送
    public static func post(_ item: PendingSendItem) {
        var list = peek()
        list.append(item)
        save(Array(list.suffix(maxQueue)))
    }

    /// 批量入队（主 App 把一次消费多条时没发完的放回队列）
    public static func post(contentsOf items: ArraySlice<PendingSendItem>) {
        var list = peek()
        list.append(contentsOf: items)
        save(Array(list.suffix(maxQueue)))
    }

    /// 主 App 轮询：读出全部并清空（读走即发，丢不了也不会重发）
    public static func consume() -> [PendingSendItem] {
        let list = peek()
        guard !list.isEmpty else { return [] }
        save([])
        return list
    }

    /// 不消费地看一眼（UI 显示队列长度用）
    public static func peek() -> [PendingSendItem] {
        if SharedStore.isAvailable {
            return SharedStore.loadPendingSends()
        }
        // 免费账号：命名剪贴板
        guard let pb = UIPasteboard(name: UIPasteboard.Name(rawValue: ConfigStore.shared.pasteboardName + ".pending"),
                                    create: false),
              let data = pb.data(forPasteboardType: "public.json"),
              let list = try? JSONDecoder().decode([PendingSendItem].self, from: data) else {
            return []
        }
        return list
    }

    private static func save(_ list: [PendingSendItem]) {
        if SharedStore.isAvailable {
            SharedStore.savePendingSends(list)
            return
        }
        guard let data = try? JSONEncoder().encode(list) else { return }
        UIPasteboard(name: UIPasteboard.Name(rawValue: ConfigStore.shared.pasteboardName + ".pending"),
                     create: true)?
            .setData(data, forPasteboardType: "public.json")
    }
}
