import Foundation
import UserNotifications

enum NotificationHelper {
    /// 扩展启动时申请本地通知权限（用户无感，弹一次系统框）。
    static func requestAuthorizationIfNeeded() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// 通用本地通知（title + body）。
    static func post(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    /// 新回复生成后发本地通知，同时提示用户半自动发送的操作路径。
    static func postReplyNotification(reply: String, session: String?) {
        let preview = reply.replacingOccurrences(of: "\n", with: " / ")
        post(title: session.map { "\($0)：新回复已生成" } ?? "新回复已生成",
             body: "「\(preview)」\n已复制到剪贴板 — 打开微信 → 长按输入框 → 粘贴 → 发送")
    }
}
