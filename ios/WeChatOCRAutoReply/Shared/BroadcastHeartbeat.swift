import Foundation
import UIKit

// =====================================================================
//  BroadcastHeartbeat：录屏扩展的生命周期探针，跨进程传递
// =====================================================================
//  解决什么问题：「直播屏幕已停止：尝试开始无效的视频会话」这个系统报错
//  有三种完全不同的原因，没有探针根本分不清：
//    ① 扩展从没启动过（签名/entitlement 问题、setup 阶段崩溃）
//       → startedAt 为空
//    ② 启动过、一帧都没处理就死了（内存超限、mediaservicesd 重置）
//       → startedAt 有值但 frames == 0
//    ③ 跑了一会儿才死（长时内存累积、被系统回收）
//       → frames > 0，对比 lastFrameAt 和 stoppedAt 即可判断
//  通道与 PendingSendBus 相同：App Group 优先，免费账号走命名剪贴板。
// =====================================================================

public struct BroadcastHeartbeat: Codable, Equatable {
    /// 扩展进程里 broadcastStarted 被调用的时间（ nil = 从未启动 ）
    public var startedAt: Date?
    /// 处理过的视频帧数（每解析一帧 +1，供判断"活着但没有输出"）
    public var frames: Int = 0
    /// 最近一次成功解析出文字的时间
    public var lastFrameAt: Date?
    /// 扩展自己观察到的停止时间（broadcastFinished；被系统杀掉时没有）
    public var finishedAt: Date?
    /// 最近一条错误（OCR/后端异常的本地描述，不涉及隐私）
    public var lastError: String = ""

    public init() {}
}

public enum BroadcastHeartbeatBus {
    private static let pasteboardName = ConfigStore.shared.pasteboardName + ".heartbeat"

    /// 扩展侧调用：覆盖写一份最新状态（轻量 JSON，<1KB）
    public static func publish(_ hb: BroadcastHeartbeat) {
        if SharedStore.isAvailable {
            SharedStore.saveHeartbeat(hb)
            return
        }
        guard let data = try? JSONEncoder().encode(hb) else { return }
        UIPasteboard(name: UIPasteboard.Name(rawValue: pasteboardName), create: true)?
            .setData(data, forPasteboardType: "public.json")
    }

    /// 主 App 轮询：读最新状态（不消费，覆盖写语义）
    public static func latest() -> BroadcastHeartbeat? {
        if SharedStore.isAvailable {
            return SharedStore.loadHeartbeat()
        }
        guard let pb = UIPasteboard(name: UIPasteboard.Name(rawValue: pasteboardName),
                                    create: false),
              let data = pb.data(forPasteboardType: "public.json"),
              let hb = try? JSONDecoder().decode(BroadcastHeartbeat.self, from: data) else {
            return nil
        }
        return hb
    }
}
