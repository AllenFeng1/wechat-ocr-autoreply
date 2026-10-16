import Foundation

// =====================================================================
//  ★★★ 对接你现有后端：只需要改这一个文件 ★★★
// =====================================================================
//
// 当前默认契约（可整体替换成你后端的样子）：
//
//    POST {serverURL}{analyzePath}
//    Header: Content-Type: application/json
//            Authorization: Bearer {apiToken}   （token 为空时不带）
//
//    请求体：
//    {
//      "device_id":  "设备 UUID（后端可据此限频）",
//      "session":    "会话名 或 null",
//      "screen_text":"OCR 识别出的整屏文本",
//      "captured_at":"ISO8601 时间"
//    }
//
//    响应体：
//    {
//      "action": "reply" | "ignore",
//      "reply":  "回复文本（action=ignore 时为 null）",
//      "reason": "可选，忽略原因"
//    }
//
// 解析是宽松的：reply 字段会依次尝试 reply / text / message / content；
// 没有 action 字段但能找到回复文本时，按 reply 处理。
// 如果你的后端契约差异更大（嵌套结构等），改下面两个类型
// 和 analyze() 的组装/解析即可，其余文件都不动。
// =====================================================================

/// 后端响应体（宽松解析：兼容常见字段命名，改这里适配你的接口）
struct AnalyzeResponseBody: Decodable {
    let action: String
    let reply: String?
    let reason: String?

    /// 按顺序尝试的回复文本字段名
    private static let replyKeys = ["reply", "text", "message", "content"]

    private struct AnyCodingKey: CodingKey {
        var stringValue: String
        var intValue: Int?
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: AnyCodingKey.self)

        // 回复文本：依次尝试常见字段名
        var foundReply: String?
        for key in Self.replyKeys {
            if let value = try? container.decode(String.self, forKey: AnyCodingKey(stringValue: key)!) {
                foundReply = value
                break
            }
        }
        self.reply = foundReply

        // action：没有该字段时，有回复文本就算 reply，否则 ignore
        if let action = try? container.decode(String.self, forKey: AnyCodingKey(stringValue: "action")!) {
            self.action = action
        } else {
            self.action = foundReply != nil ? "reply" : "ignore"
        }

        self.reason = try? container.decode(String.self, forKey: AnyCodingKey(stringValue: "reason")!)
    }
}

enum APIClient {
    /// 上传一屏 OCR 文本，返回后端的处理结果。
    /// - Parameters:
    ///   - config: 主 App 里配置的服务器地址/路径/token
    ///   - screenText: 整屏 OCR 文本
    ///   - session: 会话名（粗提取，可为 nil）
    static func analyze(
        config: AppConfig,
        screenText: String,
        session: String?,
        completion: @escaping (Result<AnalyzeResponseBody, Error>) -> Void
    ) {
        guard let base = URL(string: config.serverURL.trimmingCharacters(in: .whitespaces)),
              var components = URLComponents(url: base, resolvingAgainstBaseURL: true)
        else {
            completion(.failure(APIError.badURL))
            return
        }
        components.path = config.analyzePath
        guard let url = components.url else {
            completion(.failure(APIError.badURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15
        if !config.apiToken.isEmpty {
            request.setValue("Bearer \(config.apiToken)", forHTTPHeaderField: "Authorization")
        }

        // ---- 请求体（按你的接口调整）----
        let body: [String: Any] = [
            "device_id": config.deviceId,
            "session": session ?? NSNull(),
            "screen_text": screenText,
            "captured_at": ISO8601DateFormatter().string(from: Date()),
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: request) { data, _, error in
            if let error {
                completion(.failure(error))
                return
            }
            guard let data, !data.isEmpty else {
                completion(.failure(APIError.emptyResponse))
                return
            }
            do {
                let decoded = try JSONDecoder().decode(AnalyzeResponseBody.self, from: data)
                completion(.success(decoded))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }

    enum APIError: LocalizedError {
        case badURL
        case emptyResponse

        var errorDescription: String? {
            switch self {
            case .badURL: return "服务器地址或接口路径不合法"
            case .emptyResponse: return "后端返回为空"
            }
        }
    }
}
