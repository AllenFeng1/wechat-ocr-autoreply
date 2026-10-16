import Foundation
import OSLog
import ReplayKit
import Vision

/// OCR 流水线：帧节流 → Vision 中文识别 → 文本去重 → 上传后端 → 写共享存储 + 剪贴板 + 本地通知。
///
/// 防封号设计要点（详见仓库根目录 README）：
/// - 帧节流 1 秒一次，避免持续高负载
/// - 画面文本没变就跳过（没有新消息）
/// - 两次上传至少间隔 config.minIntervalSeconds 秒
/// - 以上都只是"少发请求"，最终频率由你的后端控制
final class OCRPipeline {
    /// 帧节流：最多每秒处理 1 帧
    private let minFrameInterval: TimeInterval = 1.0
    private let queue = DispatchQueue(label: "com.wechatocr.pipeline")
    private let logger = Logger(subsystem: "com.example.wechatocr.broadcast", category: "pipeline")

    private var running = false
    private var lastFrameTime = Date.distantPast
    private var lastUploadTime = Date.distantPast
    private var lastText = ""

    func start() { running = true }
    func pause() { running = false }
    func resume() { running = true }
    func stop() { running = false }

    /// 在系统 sample buffer 回调线程调用，内部同步做节流后的 OCR（Vision 单次约 100-300ms，可接受）。
    func enqueue(_ sampleBuffer: CMSampleBuffer) {
        guard running else { return }
        let now = Date()
        guard now.timeIntervalSince(lastFrameTime) >= minFrameInterval else { return }
        lastFrameTime = now

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let config = ConfigStore.load()
        guard config.enabled else { return }
        recognize(pixelBuffer: pixelBuffer, config: config)
    }

    // MARK: Vision OCR

    private func recognize(pixelBuffer: CVPixelBuffer, config: AppConfig) {
        let request = VNRecognizeTextRequest { [weak self] request, error in
            guard let self, error == nil,
                  let observations = request.results as? [VNRecognizedTextObservation]
            else { return }

            // 按纵向位置从上到下排序，模拟阅读顺序
            let sorted = observations.sorted { $0.boundingBox.origin.y > $1.boundingBox.origin.y }
            let lines = sorted.compactMap { $0.topCandidates(1).first?.string }
            let text = lines.joined(separator: "\n")
            self.handle(text: text, config: config)
        }

        request.recognitionLanguages = ["zh-Hans", "en-US"]
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        if #available(iOS 16.0, *) {
            request.revision = VNRecognizeTextRequestRevision3
        }

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        do {
            try handler.perform([request])
        } catch {
            logger.error("OCR perform failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: 去重 + 节流 + 上传

    private func handle(text: String, config: AppConfig) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // 画面文本和上次完全一样 → 没有新消息，跳过
        if trimmed == lastText { return }
        lastText = trimmed

        // 客户端最小上传间隔（防封号，与后端限频双重保险）
        let now = Date()
        guard now.timeIntervalSince(lastUploadTime) >= TimeInterval(config.minIntervalSeconds) else { return }
        lastUploadTime = now

        // 会话名粗提取：屏幕最顶部通常是微信导航栏标题（对方昵称）
        let lines = trimmed.split(separator: "\n", omittingEmptySubsequences: true)
        let sessionGuess = lines.first.map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        upload(text: trimmed, session: sessionGuess, config: config)
    }

    private func upload(text: String, session: String?, config: AppConfig) {
        APIClient.analyze(config: config, screenText: text, session: session) { [weak self] result in
            switch result {
            case .success(let body):
                guard body.action == "reply",
                      let reply = body.reply, !reply.trimmingCharacters(in: .whitespaces).isEmpty
                else { return }

                let message = RecognizedMessage(text: text, session: session)
                var messages = SharedStore.loadMessages()
                messages.insert(message, at: 0)
                SharedStore.saveMessages(Array(messages.prefix(50)))

                let suggestion = ReplySuggestion(
                    messageId: message.id, session: session,
                    reply: reply, createdAt: Date(), copied: false
                )
                var replies = SharedStore.loadReplies()
                replies.insert(suggestion, at: 0)
                SharedStore.saveReplies(Array(replies.prefix(50)))

                // 非越狱半自动发送的关键一步：写剪贴板 + 本地通知
                UIPasteboard.general.string = reply
                NotificationHelper.postReplyNotification(reply: reply, session: session)

            case .failure(let error):
                self?.logger.error("upload failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
