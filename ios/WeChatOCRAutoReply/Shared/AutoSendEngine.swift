import Foundation
import UIKit

// =====================================================================
//  AutoSendEngine：回复 → 微信输入框的全自动发送状态机（越狱路线）
// =====================================================================
//  前置条件（缺一不可，缺了引擎返回 failed，由上层退回"通知+人工粘贴"）：
//    1. 设置页开启自动发送
//    2. 已校准输入框/发送键坐标（校准页录入）
//    3. 设备装有 zxtouch 且已授权本地网络（连接探测见 ZXTouchClient）
//
//  流程（每条消息）：
//    随机延迟(拟人) → switch_to_app(微信) → tap 输入框(唤键盘)
//    → insert_text(逐字符) → tap 发送键 → 多条则重复
// =====================================================================

public final class AutoSendEngine {
    public static let shared = AutoSendEngine()

    public struct PendingSend {
        public var session: String
        /// 回复原文（可能含 \n = 分多条发，与 PC 端一致）
        public var reply: String
        public var friendId: Int

        public init(session: String, reply: String, friendId: Int) {
            self.session = session
            self.reply = reply
            self.friendId = friendId
        }
    }

    public enum Phase: String {
        case idle
        case waiting      // 随机延迟中（拟人化）
        case switching    // 把微信带到前台
        case tappingInput // 点输入框唤键盘
        case inserting    // 逐字符输入
        case tappingSend  // 点发送键
        case done
        case failed
    }

    /// 阶段回调（主线程）：UI 进度 / 失败原因
    public var onPhase: ((Phase, String) -> Void)?

    public private(set) var isRunning = false

    private let client = ZXTouchClient.shared
    private var cancelled = false

    private init() {}

    /// 开始一次自动发送。防重入：上一条没发完，新的直接拒（调用方走通知兜底）。
    /// - Returns: false = 被拒（正在发上一条 / 前置条件不满足）
    @discardableResult
    public func start(_ pending: PendingSend, config: AppConfig) -> Bool {
        guard !isRunning else { return false }
        guard config.autoSendEnabled, config.touchPoints.isCalibrated else {
            emit(.failed, "自动发送未开启或坐标未校准")
            return false
        }
        let lines = pending.reply.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !lines.isEmpty else {
            emit(.failed, "回复为空")
            return false
        }
        isRunning = true
        cancelled = false
        run(pending: pending, config: config, lines: lines, index: 0)
        return true
    }

    public func cancel() {
        cancelled = true
    }

    // MARK: - 状态机

    private func run(pending: PendingSend, config: AppConfig,
                     lines: [String], index: Int) {
        guard !cancelled else { finish(.failed, "已取消"); return }

        // 全部发完
        guard index < lines.count else { finish(.done, ""); return }

        // ① 随机延迟：秒回最像机器人，1.5-5s 随机（可配置）
        emit(.waiting, "第 \(index + 1)/\(lines.count) 条 · 延迟中")
        let lo = max(0.2, min(config.autoSendDelayMin, config.autoSendDelayMax))
        let hi = max(lo, max(config.autoSendDelayMin, config.autoSendDelayMax))
        let delay = Double.random(in: lo...hi)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, !self.cancelled else {
                self?.finish(.failed, "已取消")
                return
            }
            self.sendLine(lines[index], points: config.touchPoints) { [weak self] ok, err in
                guard let self else { return }
                if ok {
                    // 多条之间再隔一个随机小延迟，拟人
                    if index + 1 < lines.count {
                        let gap = Double.random(in: 0.8...2.0)
                        DispatchQueue.main.asyncAfter(deadline: .now() + gap) {
                            self.run(pending: pending, config: config,
                                     lines: lines, index: index + 1)
                        }
                    } else {
                        self.finish(.done, "")
                    }
                } else {
                    self.finish(.failed, err)
                }
            }
        }
    }

    /// 发一条：切微信 → 点输入框 → 输入 → 点发送
    private func sendLine(_ text: String, points: TouchPoints,
                          completion: @escaping (Bool, String) -> Void) {
        emit(.switching, "切换到微信")
        client.switchToApp(weChatBundleId) { [weak self] ok in
            guard let self else { return }
            guard ok else {
                completion(false, "无法切换到微信（zxtouch 服务无响应）")
                return
            }
            // 等微信回到前台（动画 ~0.4s，多留点余量）
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                guard !self.cancelled else { completion(false, "已取消"); return }
                self.emit(.tappingInput, "点击输入框")
                self.client.tap(nx: points.inputBox.x, ny: points.inputBox.y)
                // 键盘弹出动画 ~0.3s
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    guard !self.cancelled else { completion(false, "已取消"); return }
                    self.emit(.inserting, "输入 \(text.count) 字")
                    self.client.insertText(text) { result in
                        DispatchQueue.main.async {
                            switch result {
                            case .failure(let e):
                                completion(false, e.localizedDescription)
                            case .success:
                                guard !self.cancelled else {
                                    completion(false, "已取消")
                                    return
                                }
                                self.emit(.tappingSend, "点击发送")
                                self.client.tap(nx: points.sendButton.x,
                                                ny: points.sendButton.y)
                                // 发送后稍等，让微信完成发送动作再进下一条
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                                    completion(true, "")
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func finish(_ phase: Phase, _ message: String) {
        isRunning = false
        emit(phase, message)
    }

    private func emit(_ phase: Phase, _ message: String) {
        DispatchQueue.main.async { [weak self] in
            self?.onPhase?(phase, message)
        }
    }
}
