import SwiftUI

struct ContentView: View {
    @StateObject private var store = MessageStore()

    var body: some View {
        TabView {
            DashboardView(store: store)
                .tabItem {
                    Label("控制台", systemImage: "bolt.fill")
                }
            SettingsView(store: store)
                .tabItem {
                    Label("设置", systemImage: "gear")
                }
        }
    }
}

// MARK: - 控制台

struct DashboardView: View {
    @ObservedObject var store: MessageStore

    var body: some View {
        NavigationStack {
            List {
                Section("运行状态") {
                    LabeledContent("采集开关", value: store.config.enabled ? "已开启" : "已关闭")
                    LabeledContent("后端", value: store.config.serverURL + store.config.analyzePath)
                    LabeledContent("已生成回复", value: "\(store.replies.count) 条")
                    if !store.appGroupAvailable {
                        Label("App Group 未生效（免费账号），扩展将使用默认配置", systemImage: "exclamationmark.triangle")
                            .foregroundColor(.orange)
                            .font(.caption)
                    }
                }

                Section("使用流程") {
                    Text("1. 在 iPhone 上打开微信，进入某个聊天界面\n2. 下拉控制中心，长按录屏按钮，选择「WeChatOCR」\n3. 新消息到达后自动识别并生成回复，自动复制到剪贴板\n4. 点「打开微信」→ 长按输入框 → 粘贴 → 发送")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Section("最近识别与回复") {
                    if store.replies.isEmpty {
                        Text("暂无记录。按上面流程开始采集后，这里会显示后端返回的回复。")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(store.replies) { reply in
                            ReplyCard(reply: reply, store: store)
                        }
                    }
                }
            }
            .navigationTitle("微信 OCR 自动回复")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("清空") { store.clearHistory() }
                        .disabled(store.replies.isEmpty && store.messages.isEmpty)
                }
            }
        }
    }
}

struct ReplyCard: View {
    let reply: ReplySuggestion
    @ObservedObject var store: MessageStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if let session = reply.session {
                    Text(session)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Text(reply.createdAt, style: .time)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Text(reply.reply)
                .font(.body)
                .textSelection(.enabled)

            HStack {
                Button {
                    UIPasteboard.general.string = reply.reply
                    store.markCopied(reply)
                } label: {
                    Label(reply.copied ? "已复制" : "复制回复",
                          systemImage: reply.copied ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Spacer()

                Button {
                    WeChatHelper.openWeChat()
                } label: {
                    Label("打开微信", systemImage: "arrow.up.forward.app")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - 设置

struct SettingsView: View {
    @ObservedObject var store: MessageStore

    var body: some View {
        NavigationStack {
            Form {
                Section("后端对接") {
                    TextField("服务器地址（http://192.168.1.100:8000）", text: $store.config.serverURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("接口路径（/api/v1/analyze）", text: $store.config.analyzePath)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("API Token（可选）", text: $store.config.apiToken)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section("采集与防封号") {
                    Toggle("启用自动识别", isOn: $store.config.enabled)
                    Stepper(
                        "最小上传间隔：\(store.config.minIntervalSeconds) 秒",
                        value: $store.config.minIntervalSeconds,
                        in: 3...60
                    )
                }

                Section("会话白名单（逗号分隔，留空 = 不过滤）") {
                    TextField("张三, 李四", text: whitelistBinding)
                }

                Section {
                    Button("保存配置") { store.saveConfig() }
                        .frame(maxWidth: .infinity)
                } footer: {
                    Text("保存后重启一次录屏采集（结束并重新开始广播）即可生效。接口路径和字段按你后端的实际契约修改，见 Broadcast/APIClient.swift。")
                        .font(.caption)
                }
            }
            .navigationTitle("设置")
        }
    }

    private var whitelistBinding: Binding<String> {
        Binding(
            get: { store.config.whitelist.joined(separator: ", ") },
            set: { newValue in
                store.config.whitelist = newValue
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            }
        )
    }
}
