import Foundation

// MARK: - 配置（主 App 设置页写入；录屏扩展按 App Group → 命名剪贴板 → 代码默认值 的顺序解析）

public struct AppConfig: Codable, Equatable {
    /// 后端基础地址，如 https://chat.anamne.top （不要带结尾斜杠）
    public var serverURL: String
    /// 登录后拿到的 Bearer token（POST /api/auth/login 的响应字段）
    public var apiToken: String
    /// 后端账号（用于过期后自动重新登录）
    public var username: String
    /// 后端密码（个人自用App；正式分发建议改 Keychain 存储）
    public var password: String
    /// 会话白名单（微信顶部的会话名）；空 = 不过滤
    public var whitelist: [String]
    /// 采集总开关
    public var enabled: Bool
    /// 客户端节流：距上次上传至少间隔这么多秒（防封号，与后端风控双重保险）
    public var minIntervalSeconds: Int
    /// 设备唯一 ID（后端可据此限频）
    public var deviceId: String
    /// 会话绑定表：微信会话名 → 后端好友档案 id（仿 PC 端 backend_friends）
    public var friendBindings: [String: Int]

    public static let `default` = AppConfig(
        serverURL: "https://chat.anamne.top",
        apiToken: "",
        username: "",
        password: "",
        whitelist: [],
        enabled: true,
        minIntervalSeconds: 5,
        deviceId: UUID().uuidString,
        friendBindings: [:]
    )

    public init(
        serverURL: String, apiToken: String, username: String, password: String,
        whitelist: [String], enabled: Bool, minIntervalSeconds: Int,
        deviceId: String, friendBindings: [String: Int]
    ) {
        self.serverURL = serverURL
        self.apiToken = apiToken
        self.username = username
        self.password = password
        self.whitelist = whitelist
        self.enabled = enabled
        self.minIntervalSeconds = minIntervalSeconds
        self.deviceId = deviceId
        self.friendBindings = friendBindings
    }

    /// 去掉结尾斜杠，避免拼出 //api/...
    public var normalizedServerURL: String {
        serverURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    /// 宽松解码：旧版本缺字段时用默认值补，避免升级后整份配置解码失败被清空
    public init(from decoder: Decoder) throws {
        let d = AppConfig.default
        let c = try decoder.container(keyedBy: CodingKeys.self)
        serverURL = try c.decodeIfPresent(String.self, forKey: .serverURL) ?? d.serverURL
        apiToken = try c.decodeIfPresent(String.self, forKey: .apiToken) ?? ""
        username = try c.decodeIfPresent(String.self, forKey: .username) ?? ""
        password = try c.decodeIfPresent(String.self, forKey: .password) ?? ""
        whitelist = try c.decodeIfPresent([String].self, forKey: .whitelist) ?? []
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        minIntervalSeconds = try c.decodeIfPresent(Int.self, forKey: .minIntervalSeconds) ?? 5
        deviceId = try c.decodeIfPresent(String.self, forKey: .deviceId) ?? UUID().uuidString
        friendBindings = try c.decodeIfPresent([String: Int].self, forKey: .friendBindings) ?? [:]
    }
}

// MARK: - 后端好友档案（GET /api/friends 的元素形状）

public struct FriendProfile: Codable, Identifiable, Equatable {
    public var id: Int
    public var nickname: String
    public var remark: String

    public init(id: Int, nickname: String, remark: String) {
        self.id = id
        self.nickname = nickname
        self.remark = remark
    }

    private enum CodingKeys: String, CodingKey { case id, nickname, remark }

    /// 后端字段可能缺省：nickname/remark 缺了就当空串，别让一条脏数据废掉整个列表
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(Int.self, forKey: .id) ?? 0
        nickname = try c.decodeIfPresent(String.self, forKey: .nickname) ?? ""
        remark = try c.decodeIfPresent(String.self, forKey: .remark) ?? ""
    }
}

// MARK: - 识别到的消息（控制台展示用）

public struct RecognizedMessage: Codable, Identifiable, Equatable {
    public var id: String
    public var text: String
    /// 气泡归属：her = 对方，me = 自己
    public var fromMe: Bool
    /// 会话名（从屏幕顶部 OCR 提取，best-effort）
    public var session: String?
    public var capturedAt: Date

    public init(id: String = UUID().uuidString, text: String, fromMe: Bool,
                session: String? = nil, capturedAt: Date = Date()) {
        self.id = id
        self.text = text
        self.fromMe = fromMe
        self.session = session
        self.capturedAt = capturedAt
    }
}

// MARK: - 后端返回的回复建议

public struct ReplySuggestion: Codable, Identifiable, Equatable {
    public var id: String
    /// 会话名
    public var session: String?
    /// 好友档案 id（0 = 未绑定）
    public var friendId: Int
    /// 回复原文（可能含 \n = 建议分多条发送，与 PC 端一致）
    public var reply: String
    public var createdAt: Date
    public var copied: Bool
    /// 用户实际处理结果：pending / sent / edited / cancelled（回传 POST /chat/{fid}/outcome）
    public var outcome: String
    /// 后端附带信息（破冰 / 错误原因等）
    public var note: String

    public init(
        id: String = UUID().uuidString, session: String? = nil, friendId: Int = 0,
        reply: String, createdAt: Date = Date(), copied: Bool = false,
        outcome: String = "pending", note: String = ""
    ) {
        self.id = id
        self.session = session
        self.friendId = friendId
        self.reply = reply
        self.createdAt = createdAt
        self.copied = copied
        self.outcome = outcome
        self.note = note
    }

    /// 按 \n 拆成的多条（微信里逐条发）
    public var lines: [String] {
        reply.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

// MARK: - generate 接口的响应体

/// POST /api/chat/{fid}/generate 的返回。
/// 注意 emotion_detected / jev_pending 语义（PC 端 core/engine.py）：
/// 后端把判断权交回来时 reply 为空，PC 端按后端建议自动补第二轮（_follow_up）。
public struct GenerateResult: Decodable, Equatable {
    public var reply: String
    public var replyRaw: String
    public var groupId: String
    public var emotionDetected: Bool
    public var jevPending: Bool
    public var icebreaker: Bool
    public var error: String

    private enum CodingKeys: String, CodingKey {
        case reply, replyRaw = "reply_raw", groupId = "group_id",
             emotionDetected = "emotion_detected", jevPending = "jev_pending",
             icebreaker, error
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        reply = try c.decodeIfPresent(String.self, forKey: .reply) ?? ""
        replyRaw = try c.decodeIfPresent(String.self, forKey: .replyRaw) ?? ""
        groupId = try c.decodeIfPresent(String.self, forKey: .groupId) ?? ""
        emotionDetected = try c.decodeIfPresent(Bool.self, forKey: .emotionDetected) ?? false
        jevPending = try c.decodeIfPresent(Bool.self, forKey: .jevPending) ?? false
        icebreaker = try c.decodeIfPresent(Bool.self, forKey: .icebreaker) ?? false
        error = try c.decodeIfPresent(String.self, forKey: .error) ?? ""
    }
}

// MARK: - OCR 解析出的单行消息

/// 气泡归属判定（对应 PC 端 app/ocr.py 的 who_said：按框内颜色分类）
public enum BubbleKind: String {
    case her = "her"   // 对方（非绿底、文字对比度高）
    case me = "me"     // 自己（绿底）
    case gray = "gray" // 时间戳/系统提示/群内昵称（灰字，跳过）
    case image = "image" // 图片/表情包里的字（颜色杂，跳过）
}

public struct ParsedLine {
    public var text: String
    public var kind: BubbleKind
    /// 距屏幕顶部的比例（0 = 最顶）
    public var top: CGFloat
    /// 框中心 x 占屏宽比例
    public var centerX: CGFloat

    public init(text: String, kind: BubbleKind, top: CGFloat, centerX: CGFloat) {
        self.text = text
        self.kind = kind
        self.top = top
        self.centerX = centerX
    }
}
