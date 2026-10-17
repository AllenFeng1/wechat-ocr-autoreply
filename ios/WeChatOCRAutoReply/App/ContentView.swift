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

    /// 最近出现过的会话名（从回复记录里提取，倒序去重）
    private var recentSessions: [String] {
        var seen = Set<String>()
        var out: [String] = []
        for r in store.replies.reversed() {
            guard let s = r.session, !s.isEmpty, !seen.contains(s) else { continue }
            seen.insert(s)
            out.append(s)
        }
        return out
    }

    var body: some View {
        NavigationStack {
            List {
                Section("运行状态") {
                    LabeledContent("采集开关", value: store.config.enabled ? "已开启" : "已关闭")
                    LabeledContent("后端", value: store.config.normalizedServerURL)
                    LabeledContent("登录", value: store.config.apiToken.isEmpty ? "未登录" : "已登录")
                    LabeledContent("会话绑定", value: "\(store.config.friendBindings.count) 个")
                    LabeledContent("已生成回复", value: "\(store.replies.count) 条")
                    if !store.appGroupAvailable {
                        Label("App Group 未生效（免费账号）：扩展通过命名剪贴板读配置，主 App 保存后即生效", systemImage: "exclamationmark.triangle")
                            .foregroundColor(.orange)
                            .font(.caption)
                    }
                }

                Section("使用流程") {
                    Text("1. 在 iPhone 上打开微信，进入某个聊天界面\n2. 下拉控制中心，长按录屏按钮，选择「WeChatOCR」\n3. 对方来消息 → 后端生成回复 → 通知弹出\n4. 打开微信 → 长按输入框 → 粘贴 → 发送（分行的逐条发）")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if !recentSessions.isEmpty {
                    Section("会话绑定状态") {
                        ForEach(recentSessions, id: \.self) { session in
                            HStack {
                                Text(session)
                                Spacer()
                                if let fid = store.config.friendBindings[session], fid > 0 {
                                    let name = store.friends.first(where: { $0.id == fid })?.nickname ?? "#\(fid)"
                                    Text("已绑 \(name)")
                                        .font(.caption)
                                        .foregroundColor(.green)
                                } else {
                                    Text("未绑定")
                                        .font(.caption)
                                        .foregroundColor(.orange)
                                }
                            }
                        }
                    }
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
                if reply.friendId > 0 {
                    Text("#\(reply.friendId)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Text(reply.createdAt, style: .time)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            if !reply.note.isEmpty {
                Text(reply.note)
                    .font(.caption)
                    .foregroundColor(.orange)
            }

            if reply.reply.isEmpty {
                Text("（没有生成回复）")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                // 多行回复：分行展示，点单行复制该行（微信里逐条发）
                ForEach(Array(reply.lines.enumerated()), id: \.offset) { _, line in
                    HStack(alignment: .top) {
                        Text(line)
                            .font(.body)
                            .textSelection(.enabled)
                        Spacer()
                        Button {
                            UIPasteboard.general.string = line
                            store.markCopied(reply)
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .font(.caption)
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }

            if reply.outcome == "pending", !reply.reply.isEmpty {
                HStack {
                    Button {
                        store.reportOutcome(reply, action: "sent")
                    } label: {
                        Label("已发送", systemImage: "paperplane")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                    Button {
                        store.reportOutcome(reply, action: "cancelled")
                    } label: {
                        Label("没发", systemImage: "xmark")
                    }
                    .buttonStyle(.bordered)
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
            } else if reply.outcome != "pending" {
                Text("已标记：\(outcomeText(reply.outcome))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func outcomeText(_ outcome: String) -> String {
        switch outcome {
        case "sent": return "原样发送"
        case "edited": return "改后发送"
        case "cancelled": return "没有发送"
        default: return outcome
        }
    }
}

// MARK: - 设置

struct SettingsView: View {
    @ObservedObject var store: MessageStore

    var body: some View {
        NavigationStack {
            Form {
                Section("后端对接") {
                    TextField("服务器地址（https://chat.anamne.top）", text: $store.config.serverURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    HStack {
                        Button("测试连接") { store.testConnection() }
                        Spacer()
                        if store.busy {
                            ProgressView()
                        }
                    }
                    if !store.status.isEmpty {
                        Text(store.status)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Section("登录（AnamneChat 账号）") {
                    TextField("用户名", text: $store.config.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("密码", text: $store.config.password)
                    Button("登录并保存") { store.login() }
                        .disabled(store.busy)
                }

                Section("好友档案") {
                    HStack {
                        Text("共 \(store.friends.count) 个")
                        Spacer()
                        Button("刷新列表") { store.refreshFriends() }
                            .disabled(store.busy)
                    }
                }

                Section("会话绑定") {
                    Text("录屏时识别到的会话，在这里绑到后端好友档案。没绑定的会话不会生成回复，也不会自动建档。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    ForEach(boundSessions(), id: \.self) { session in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(session)
                                .font(.subheadline)
                            Picker("好友档案", selection: binding(for: session)) {
                                Text("未绑定").tag(0)
                                ForEach(store.friends) { f in
                                    Text(f.remark.isEmpty ? f.nickname : "\(f.nickname)（\(f.remark)）")
                                        .tag(f.id)
                                }
                            }
                            .pickerStyle(.menu)
                            HStack {
                                Button("用会话名新建档案并绑定") {
                                    store.createAndBind(session: session)
                                }
                                .font(.caption)
                                .disabled(store.busy)
                                Spacer()
                                if (store.config.friendBindings[session] ?? 0) > 0 {
                                    Button("解绑", role: .destructive) {
                                        store.unbind(session: session)
                                    }
                                    .font(.caption)
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
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
                    Text("保存后重启一次录屏采集（结束并重新开始广播）即可生效。")
                        .font(.caption)
                }
            }
            .navigationTitle("设置")
        }
    }

    /// 已绑定 + 最近出现过的会话
    private func boundSessions() -> [String] {
        var out = Array(store.config.friendBindings.keys)
        var seen = Set(out)
        for r in store.replies.reversed() {
            guard let s = r.session, !s.isEmpty, !seen.contains(s) else { continue }
            seen.insert(s)
            out.append(s)
        }
        return out
    }

    private func binding(for session: String) -> Binding<Int> {
        Binding(
            get: { store.config.friendBindings[session] ?? 0 },
            set: { newValue in
                if newValue > 0 {
                    store.bind(session: session, friendId: newValue)
                } else {
                    store.unbind(session: session)
                }
            }
        )
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
