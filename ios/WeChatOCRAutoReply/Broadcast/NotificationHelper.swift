import Foundation
import UserNotifications

enum NotificationHelper {
    /// 扩展启动时申请本地通知权限（用户无感，弹一次系统框）。
    static func requestAuthorizationIfNeeded() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// 新回复生成后发本地通知，同时提示用户半自动发送的操作路径。
    static func postReplyNotification(reply: String, session: String?) {
        let content = UNMutableNotificationContent()
        content.title = session.map { "\($0)：新回复已生成" } ?? "新回复已生成"
        content.body = "「\(reply)」\n已复制到剪贴板 — 打开微信 → 长按输入框 → 粘贴 → 发送"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
