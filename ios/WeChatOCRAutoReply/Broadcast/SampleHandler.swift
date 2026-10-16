import OSLog
import ReplayKit

/// 录屏广播扩展入口：用户在控制中心长按录屏、选择本 App 后启动。
/// 全屏视频帧经 OCRPipeline 处理后送 Vision OCR，再上传后端。
class SampleHandler: RPBroadcastSampleHandler {
    private let pipeline = OCRPipeline()
    private let logger = Logger(subsystem: "com.allenfeng1.wechatocr.broadcast", category: "sample")

    override func broadcastStarted(withSetupInfo setupInfo: [String : NSObject]?) {
        logger.info("WeChatOCR broadcast started")
        NotificationHelper.requestAuthorizationIfNeeded()
        pipeline.start()
    }

    override func broadcastPaused() {
        pipeline.pause()
    }

    override func broadcastResumed() {
        pipeline.resume()
    }

    override func broadcastFinished() {
        pipeline.stop()
    }

    /// 系统每产生一帧屏幕内容就回调这里。必须快速返回，重活丢给节流逻辑。
    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        guard sampleBufferType == .video else { return }
        pipeline.enqueue(sampleBuffer)
    }
}
