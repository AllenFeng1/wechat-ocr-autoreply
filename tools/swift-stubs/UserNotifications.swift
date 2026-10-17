// =====================================================================
//  UserNotifications 桩模块 —— 仅供 Windows 本地类型检查（preflight）使用。
// =====================================================================
import Foundation

public struct UNAuthorizationOptions: OptionSet {
    public var rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }

    public static let badge      = UNAuthorizationOptions(rawValue: 1)
    public static let sound      = UNAuthorizationOptions(rawValue: 2)
    public static let alert      = UNAuthorizationOptions(rawValue: 4)
    public static let carPlay    = UNAuthorizationOptions(rawValue: 8)
    public static let criticalAlert = UNAuthorizationOptions(rawValue: 16)
    public static let provisional = UNAuthorizationOptions(rawValue: 32)
    public static let providesAppNotificationSettings = UNAuthorizationOptions(rawValue: 64)
    public static let announcement = UNAuthorizationOptions(rawValue: 128)
}

public struct UNNotificationSound {
    public static let `default` = UNNotificationSound()
}

open class UNNotificationContent {
    public init() {}
}

public final class UNMutableNotificationContent: UNNotificationContent {
    public override init() {}
    public var title: String = ""
    public var subtitle: String = ""
    public var body: String = ""
    public var sound: UNNotificationSound?
}

open class UNNotificationTrigger {}

public final class UNNotificationRequest {
    public let identifier: String
    public let content: UNNotificationContent
    public let trigger: UNNotificationTrigger?

    public init(identifier: String, content: UNNotificationContent,
                trigger: UNNotificationTrigger?) {
        self.identifier = identifier
        self.content = content
        self.trigger = trigger
    }
}

public final class UNUserNotificationCenter {
    public class func current() -> UNUserNotificationCenter { UNUserNotificationCenter() }

    public func requestAuthorization(options: UNAuthorizationOptions,
                                     completionHandler: @escaping (Bool, Error?) -> Void) {}
    public func add(_ request: UNNotificationRequest,
                    withCompletionHandler completionHandler: ((Error?) -> Void)? = nil) {}
}
