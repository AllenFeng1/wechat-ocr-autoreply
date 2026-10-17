import Foundation

// =====================================================================
//  AnamneChat（MiraMate）后端客户端 —— iOS 端唯一与后端对话的文件
// =====================================================================
//  契约来源（源码交接包 2026-10-17）：
//    后端 src/MiraMate/web_api/pc_api.py + auth_api.py
//    PC 端 core/backend_client.py + core/engine.py + app/settings.py
//
//  接口一览（base = https://chat.anamne.top，不带结尾斜杠）：
//
//  1) POST /api/auth/login
//     请求 {username, password}
//     200  {ok, token, ...}；401 {"detail":"用户名或密码错误"}
//
//  2) GET  /api/friends                      （Authorization: Bearer token）
//     200  [{id, nickname, remark, persona, relationship, ...}]
//
//  3) POST /api/friends                      （同上鉴权）
//     请求 {nickname, remark, ...} → {id, nickname, remark}
//     ⚠️ 只在用户显式操作时调用，绝不拿 OCR 出来的会话名自动建档
//
//  4) POST /api/chat/{friend_id}/generate    （核心）
//     请求 {incoming, action:"auto", group_id:""}
//       incoming = 对方最新消息（末尾连续几条她的话，\n 连接；≤2000 字）
//     200  {reply, reply_raw, group_id, emotion_detected, icebreaker?, error?}
//       reply 里的 \n = 建议分多条发（PC 端 split_reply 逐条发）
//       emotion_detected=true 时 reply 为空 → 按后端建议补第二轮
//         （action=plain + force_mood；PC 端 engine._follow_up）
//       jev_pending=true 时 reply 为空 → 补第二轮 action=jev_inject
//         第二轮不带 incoming，只带第一轮的 group_id（不会写重历史）
//       error 非空 = 后端明确失败（如禁句被丢弃），**不要重试**
//       ⚠️ 本接口有副作用：incoming 会入库。同一批内容不要反复调
//
//  5) POST /api/chat/{friend_id}/outcome
//     请求 {action:"sent"|"edited"|"cancelled", final_text}
//     用户实际怎么处理的（保持后端历史准确）
//
//  换后端只改这个文件；协议细节如与线上不一致，以 pc_api.py 为准。
// =====================================================================

public enum BackendError: Error, Equatable {
    case badURL              // 地址没填/格式不对
    case notLoggedIn         // 没有 token
    case http(Int, String)   // 状态码 + 响应摘要
    case transport(String)   // 网络层错误
    case decode(String)      // 响应不是预期 JSON
    case backend(String)     // 后端 200 + error 字段

    public var message: String {
        switch self {
        case .badURL: return "后端地址不对（要 https://主机 这种）"
        case .notLoggedIn: return "还没登录后端"
        case .http(let code, let detail):
            if code == 401 { return "登录状态失效（401），请重新登录" }
            if code == 404 { return "后端没有这个好友档案（404），去 App 里重新绑定" }
            return "后端返回 HTTP \(code)\(detail.isEmpty ? "" : "：\(detail)")"
        case .transport(let s): return "连不上后端：\(s)"
        case .decode(let s): return "后端响应解析失败：\(s)"
        case .backend(let s): return s
        }
    }
}

public struct BackendClient {
    public let base: String
    public var token: String

    public init(base: String, token: String = "") {
        self.base = base.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.token = token
    }

    // MARK: - 内部：JSON 请求

    private func request(
        _ path: String,
        method: String = "GET",
        body: [String: Any]? = nil,
        timeout: TimeInterval = 30,
        auth: Bool = true
    ) throws -> Data {
        guard !base.isEmpty,
              let url = URL(string: base + path) else {
            throw BackendError.badURL
        }
        var req = URLRequest(url: url, timeoutInterval: timeout)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if auth, !token.isEmpty {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }

        var result: Result<Data, Error>?
        let sem = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: req) { data, resp, err in
            defer { sem.signal() }
            if let err { result = .failure(err); return }
            guard let http = resp as? HTTPURLResponse else {
                result = .failure(URLError(.badServerResponse)); return
            }
            guard (200..<300).contains(http.statusCode) else {
                let detail = (data.flatMap { String(data: $0, encoding: .utf8) } ?? "")
                    .prefix(300).description
                result = .failure(BackendError.http(http.statusCode, detail))
                return
            }
            result = .success(data ?? Data())
        }.resume()
        sem.wait()

        switch result {
        case .success(let data): return data
        case .failure(let e):
            if let be = e as? BackendError { throw be }
            throw BackendError.transport(e.localizedDescription)
        case .none:
            throw BackendError.transport("请求被中断")
        }
    }

    private func json(_ path: String, method: String = "GET", body: [String: Any]? = nil,
                      timeout: TimeInterval = 30, auth: Bool = true) throws -> Any {
        let data = try request(path, method: method, body: body, timeout: timeout, auth: auth)
        guard let obj = try? JSONSerialization.jsonObject(with: data) else {
            throw BackendError.decode(String(data: data, encoding: .utf8)?.prefix(200) ?? "")
        }
        return obj
    }

    // MARK: - 1) 登录

    /// POST /api/auth/login → token。失败抛 401。
    @discardableResult
    public func login(username: String, password: String) throws -> String {
        let obj = try json("/api/auth/login", method: "POST",
                           body: ["username": username, "password": password],
                           auth: false)
        guard let dict = obj as? [String: Any],
              let token = (dict["token"] as? String)?.trimmingCharacters(in: .whitespaces),
              !token.isEmpty else {
            throw BackendError.decode("登录响应里没有 token")
        }
        self.token = token
        return token
    }

    // MARK: - 2) 好友列表

    public func listFriends() throws -> [FriendProfile] {
        let obj = try json("/api/friends")
        guard let arr = obj as? [[String: Any]] else {
            throw BackendError.decode("/api/friends 不是数组")
        }
        let data = try JSONSerialization.data(withJSONObject: arr)
        return (try? JSONDecoder().decode([FriendProfile].self, from: data)) ?? []
    }

    // MARK: - 3) 新建好友档案（仅用户显式触发）

    @discardableResult
    public func createFriend(nickname: String, remark: String = "") throws -> Int {
        var body: [String: Any] = ["nickname": nickname]
        if !remark.isEmpty { body["remark"] = remark }
        let obj = try json("/api/friends", method: "POST", body: body)
        guard let dict = obj as? [String: Any], let id = dict["id"] as? Int else {
            throw BackendError.decode("建档响应里没有 id")
        }
        return id
    }

    // MARK: - 4) 生成回复（核心；有副作用，别反复调同一内容）

    public struct GenerateResponse {
        public var reply: String        // 可能含 \n（分多条发）
        public var groupId: String
        public var note: String         // 破冰 / 错误等说明
    }

    /// 一次调用 = 对方消息入库 + 生成回复。
    /// emotion_detected / jev_pending 时按后端建议自动补第二轮（同 PC 端 _follow_up）。
    public func generate(friendId: Int, incoming: String,
                         timeout: TimeInterval = 60) throws -> GenerateResponse {
        var got = try rawGenerate(friendId: friendId, incoming: incoming,
                                  action: "auto", groupId: "",
                                  forceMood: nil, jevContext: nil, timeout: timeout)

        // 后端把判断权交回来：PC 端无人值守，按它自己的建议补第二轮
        var note = ""
        if got.emotionDetected || got.jevPending {
            let gid = got.groupId
            if !gid.isEmpty {
                note = got.emotionDetected ? "对方情绪异常 · 按后端建议共情安慰" : "JEV 挂起 · 按后端建议注入判断"
                let action = got.emotionDetected ? "plain" : "jev_inject"
                let mood = got.emotionDetected ? "comfort" : nil
                got = try rawGenerate(friendId: friendId, incoming: "",
                                      action: action, groupId: gid,
                                      forceMood: mood, jevContext: nil, timeout: timeout)
            } else {
                note = "后端把判断权交回给你，但没有给 group_id，无法自动补轮"
            }
        }

        if !got.error.isEmpty {
            throw BackendError.backend(got.error)
        }
        if got.reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw BackendError.backend("后端没有生成出回复")
        }
        var out = GenerateResponse(reply: got.reply, groupId: got.groupId, note: note)
        if got.icebreaker { out.note = (note.isEmpty ? "" : note + " · ") + "新好友破冰" }
        return out
    }

    private func rawGenerate(friendId: Int, incoming: String, action: String,
                             groupId: String, forceMood: String?, jevContext: [String: Any]?,
                             timeout: TimeInterval) throws -> GenerateResult {
        var body: [String: Any] = [
            "incoming": incoming,
            "action": action,
            "group_id": groupId,
        ]
        if let forceMood { body["force_mood"] = forceMood }
        if let jevContext { body["jev_context"] = jevContext }
        let data = try request("/api/chat/\(friendId)/generate",
                               method: "POST", body: body, timeout: timeout)
        guard let r = try? JSONDecoder().decode(GenerateResult.self, from: data) else {
            throw BackendError.decode(String(data: data, encoding: .utf8)?.prefix(200) ?? "")
        }
        return r
    }

    // MARK: - 5) 实际上传结局上报

    /// action: sent（原样发了）/ edited（改了后发的，finalText 填实际内容）/ cancelled（没发）
    public func reportOutcome(friendId: Int, action: String, finalText: String = "",
                              timeout: TimeInterval = 10) throws {
        _ = try request("/api/chat/\(friendId)/outcome", method: "POST",
                        body: ["action": action, "final_text": finalText],
                        timeout: timeout)
    }

    // MARK: - 连通性自检（设置页「测试连接」用）

    /// GET /api/health 不需要鉴权；返回 nil = 通。
    public static func healthCheck(base: String) -> String? {
        guard let url = URL(string: base.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                                + "/api/health") else { return "地址格式不对" }
        var req = URLRequest(url: url, timeoutInterval: 8)
        req.httpMethod = "GET"
        let sem = DispatchSemaphore(value: 0)
        var problem: String?
        URLSession.shared.dataTask(with: req) { _, resp, err in
            defer { sem.signal() }
            if let err { problem = err.localizedDescription; return }
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
                problem = "HTTP \((resp as? HTTPURLResponse)?.statusCode ?? -1)"
                return
            }
        }.resume()
        sem.wait()
        return problem
    }
}
