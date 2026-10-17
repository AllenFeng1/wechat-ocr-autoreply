import ReplayKit
import UIKit
import os

/// 录屏广播扩展入口：用户在控制中心长按录屏、选择本 App 后启动。
/// 全屏视频帧经 OCRPipeline 解析（会话名 + 她/我消息），
/// 再走 AnamneChat 后端生成回复，写剪贴板 + 弹本地通知（半自动发送，防封号）。
class SampleHandler: RPBroadcastSampleHandler {
    private let pipeline = OCRPipeline()
    private let store = ConfigStore.shared
    private let logger = Logger(subsystem: "com.allenfeng1.wechatocr.broadcast",
                                category: "SampleHandler")

    /// 帧处理串行队列。ReplayKit 要求 processSampleBuffer 尽快返回，
    /// 重活（OCR + 网络）全丢这里；上一帧没处理完就丢帧——
    /// iOS 会杀掉“跟不上帧率”的广播扩展，表现就是用户看到的「直播已停止」。
    private let workQueue = DispatchQueue(label: "wechatocr.ocr", qos: .userInitiated)
    private var isBusy = false
    private var frameCount = 0
    private var dropCount = 0

    override func broadcastStarted(withSetupInfo setupInfo: [String : NSObject]?) {
        os_log(.info, "WeChatOCR broadcast started")
        NotificationHelper.requestAuthorizationIfNeeded()
        pipeline.resetSignature()
        pipeline.minIntervalSeconds = max(1, store.loadForExtension().minIntervalSeconds)
        isBusy = false
        frameCount = 0
        dropCount = 0
    }

    override func broadcastPaused() {
        os_log(.info, "WeChatOCR broadcast paused")
    }

    override func broadcastResumed() {
        os_log(.info, "WeChatOCR broadcast resumed")
    }

    override func broadcastFinished() {
        os_log(.info, "WeChatOCR broadcast finished")
        pipeline.resetSignature()
    }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer,
                                      with sampleBufferType: RPSampleBufferType) {
        guard sampleBufferType == .video else { return }
        frameCount += 1

        // 丢帧保护：上一帧还在处理就跳过（等 OCR 的几秒里后续帧全丢，只保留最新节奏）
        guard !isBusy else {
            dropCount += 1
            if dropCount % 60 == 1 {
                os_log(.info, "busy, dropped \(self.dropCount, privacy: .public) / \(self.frameCount, privacy: .public)")
            }
            return
        }

        let cfg = store.loadForExtension()
        guard cfg.enabled else { return }

        workQueue.async { [weak self] in
            guard let self else { return }
            self.isBusy = true
            defer { self.isBusy = false }
            autoreleasepool {
                guard let parsed = self.pipeline.parse(sampleBuffer: sampleBuffer) else { return }

                let session = parsed.session
                let incoming = parsed.incomingFromHer
                guard !session.isEmpty, !incoming.isEmpty else { return }

                // 白名单（会话名不在名单里就跳过；空 = 不过滤）
                if !cfg.whitelist.isEmpty && !cfg.whitelist.contains(session) { return }

                // 内容没变就不重复上传（同一条消息只生成一次）
                guard self.pipeline.isNewContent(session: session, incoming: incoming) else { return }

                self.handleNewMessage(session: session, incoming: incoming, cfg: cfg)
            }
        }
    }

    // MARK: - 核心：新消息 → 后端 → 回复

    private func handleNewMessage(session: String, incoming: String, cfg: AppConfig) {
        // ① 没登录：通知引导去主 App 登录
        if cfg.apiToken.isEmpty {
            notify(title: "WeChatOCR 未登录",
                   body: "请打开主 App，在后端设置里登录 \(cfg.serverURL)")
            record(session: session, friendId: 0, reply: "",
                   note: "未登录后端，请先在主 App 登录")
            return
        }

        // ② 解析好友：绑定表 → 自动匹配 → 未绑定（绝不自动建档）
        var friends = store.cachedFriends()
        if friends.isEmpty, let fetched = try? BackendClient(base: cfg.normalizedServerURL,
                                                             token: cfg.apiToken).listFriends() {
            friends = fetched
            store.cacheFriends(fetched)
        }
        let friendId = store.resolveFriendId(session: session, friends: friends)
        guard friendId > 0 else {
            notify(title: "「\(session)」还没绑定后端好友",
                   body: "打开 WeChatOCR 主 App → 设置 → 绑定这个会话（不会自动建档）")
            record(session: session, friendId: 0, reply: "",
                   note: "会话未绑定好友档案")
            return
        }

        // ③ 调后端生成（有副作用：incoming 会入库，失败不重试同一内容）
        let client = BackendClient(base: cfg.normalizedServerURL, token: cfg.apiToken)
        let result: BackendClient.GenerateResponse
        do {
            result = try client.generate(friendId: friendId, incoming: incoming)
        } catch let e as BackendError {
            logger.error("generate failed: \(e.message, privacy: .public)")
            notify(title: "「\(session)」生成失败", body: e.message)
            record(session: session, friendId: friendId, reply: "", note: e.message)
            return
        } catch {
            notify(title: "「\(session)」生成失败", body: error.localizedDescription)
            record(session: session, friendId: friendId, reply: "",
                   note: error.localizedDescription)
            return
        }

        // ④ 回复写剪贴板（多行保留 \n，用户可在微信里逐条粘贴发送）
        UIPasteboard.general.string = result.reply

        // ⑤ 本地通知：点开 App 可见完整回复；发送由人手动完成（防封号）
        let preview = result.reply.replacingOccurrences(of: "\n", with: " / ")
        notify(title: "「\(session)」回复已就绪",
               body: preview + (result.note.isEmpty ? "" : "（\(result.note)）"))

        // ⑥ 控制台留痕
        record(session: session, friendId: friendId, reply: result.reply, note: result.note)
    }

    // MARK: - 通知 & 控制台

    private func notify(title: String, body: String) {
        NotificationHelper.post(title: title, body: body)
    }

    private func record(session: String, friendId: Int, reply: String, note: String) {
        let suggestion = ReplySuggestion(session: session, friendId: friendId,
                                         reply: reply, note: note)
        var list = store.loadReplies()
        list.append(suggestion)
        store.saveReplies(list)
        // 免费账号模式（无 App Group）下，主 App 靠命名剪贴板收到新回复
        store.publishReplyViaPasteboard(suggestion)
    }
}
