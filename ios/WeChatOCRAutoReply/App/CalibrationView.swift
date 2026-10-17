import SwiftUI
import Foundation

// =====================================================================
//  CalibrationView：自动发送坐标校准（两步：输入框 → 发送键）
// =====================================================================
//  用法：先打开微信的目标聊天页（键盘弹出状态），回到本页，
//  按提示依次点击「输入框中心」和「键盘上的发送键」。
//  坐标存为归一化值（0-1），换机型/微信版本只需重新校准。
// =====================================================================

struct CalibrationView: View {
    @ObservedObject var store: MessageStore
    @Environment(\.dismiss) private var dismiss

    /// 0 = 等点输入框，1 = 等点发送键，2 = 完成
    @State private var step = 0
    @State private var inputBox: CGPoint?
    @State private var sendButton: CGPoint?

    private func fmt(_ v: Double) -> String { String(format: "%.2f", v) }

    var body: some View {
        ZStack {
            // 全屏点击捕获（记录归一化坐标）
            // 注意：不能用 onTapGesture(coordinateSpace:perform:)——那是 iOS 17+ API，
            // 本工程部署目标 16.0。DragGesture(minimumDistance: 0) 从 iOS 13 起可用，
            // onEnded 的 value.location 就是点击位置，行为等价。
            GeometryReader { geo in
                Color.black.opacity(0.85)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0, coordinateSpace: .global)
                            .onEnded { value in
                                let location = value.location
                                let point = CGPoint(
                                    x: min(max(location.x / geo.size.width, 0), 1),
                                    y: min(max(location.y / geo.size.height, 0), 1)
                                )
                                switch step {
                                case 0:
                                    inputBox = point
                                    step = 1
                                case 1:
                                    sendButton = point
                                    step = 2
                                default: break
                                }
                            }
                    )
            }

            // 说明卡片 + 操作按钮
            VStack(spacing: 16) {
                Spacer()

                VStack(spacing: 12) {
                    Text(step == 0 ? "第 1 步 / 共 2 步" : step == 1 ? "第 2 步 / 共 2 步" : "校准完成")
                        .font(.headline)
                    Text(step == 0
                         ? "打开微信，进入一个聊天窗口并弹出键盘。\n回到本页，点击屏幕底部输入框的中心位置。"
                         : step == 1
                         ? "保持键盘弹出，点击右下角蓝色「发送」键的中心位置。"
                         : "已记录两个坐标，保存后自动发送即可使用。")
                        .font(.subheadline)
                        .multilineTextAlignment(.center)

                    if let inputBox {
                        Label("输入框：(\(fmt(inputBox.x)), \(fmt(inputBox.y)))",
                              systemImage: "text.cursor")
                            .font(.caption)
                    }
                    if let sendButton {
                        Label("发送键：(\(fmt(sendButton.x)), \(fmt(sendButton.y)))",
                              systemImage: "paperplane")
                            .font(.caption)
                    }
                }
                .padding()
                .background(Color.black.opacity(0.6))
                .cornerRadius(16)
                .padding(.horizontal, 24)

                Spacer()

                VStack(spacing: 12) {
                    if step == 2 {
                        Button("保存并开启自动发送") {
                            store.config.touchPoints = TouchPoints(
                                inputBox: inputBox ?? TouchPoints.default.inputBox,
                                sendButton: sendButton ?? TouchPoints.default.sendButton
                            )
                            store.config.autoSendEnabled = true
                            store.saveConfig()
                            dismiss()
                        }
                        .buttonStyle(.borderedProminent)

                        Button("重新校准") {
                            step = 0
                            inputBox = nil
                            sendButton = nil
                        }
                    }
                    Button("取消", role: .cancel) { dismiss() }
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 40)
            }
        }
    }
}
