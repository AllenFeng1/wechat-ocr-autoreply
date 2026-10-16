import Foundation

// MARK: - 配置（主 App 设置页写入，通过 App Group 与录屏扩展共享）

public struct AppConfig: Codable, Equatable {
    /// 后端基础地址，如 http://192.168.1.100:8000
    public var serverURL: String
    /// 可选 Bearer Token（你的后端需要鉴权时填）
    public var apiToken: String
    /// 分析接口路径（相对 serverURL）
    public var analyzePath: String
    /// 会话白名单（微信备注/昵称）；空 = 不过滤
    public var whitelist: [String]
    /// 采集总开关
    public var enabled: Bool
    /// 客户端节流：距上次上传至少间隔这么多秒（防封号，与服务器端双重保险）
    public var minIntervalSeconds: Int
    /// 设备唯一 ID（服务器端按此限频）
    public var deviceId: String

    public static let `default` = AppConfig(
        serverURL: "http://192.168.1.100:8000",
        apiToken: "",
        analyzePath: "/api/v1/analyze",
        whitelist: [],
        enabled: true,
        minIntervalSeconds: 5,
        deviceId: UUID().uuidString
    )

    public init(
        serverURL: String, apiToken: String, analyzePath: String,
        whitelist: [String], enabled: Bool, minIntervalSeconds: Int, deviceId: String
    ) {
        self.serverURL = serverURL
        self.apiToken = apiToken
        self.analyzePath = analyzePath
        self.whitelist = whitelist
        self.enabled = enabled
        self.minIntervalSeconds = minIntervalSeconds
        self.deviceId = deviceId
    }
}

// MARK: - 识别到的消息

public struct RecognizedMessage: Codable, Identifiable, Equatable {
    public var id: String
    public var text: String
    /// 会话名（从屏幕顶部 OCR 文本粗提取，best-effort）
    public var session: String?
    public var capturedAt: Date

    public init(id: String = UUID().uuidString, text: String, session: String? = nil, capturedAt: Date = Date()) {
        self.id = id
        self.text = text
        self.session = session
        self.capturedAt = capturedAt
    }
}

// MARK: - 后端返回的回复建议

public struct ReplySuggestion: Codable, Identifiable, Equatable {
    public var id: String
    public var messageId: String
    public var session: String?
    public var reply: String
    public var createdAt: Date
    public var copied: Bool

    public init(
        id: String = UUID().uuidString, messageId: String, session: String? = nil,
        reply: String, createdAt: Date = Date(), copied: Bool = false
    ) {
        self.id = id
        self.messageId = messageId
        self.session = session
        self.reply = reply
        self.createdAt = createdAt
        self.copied = copied
    }
}
