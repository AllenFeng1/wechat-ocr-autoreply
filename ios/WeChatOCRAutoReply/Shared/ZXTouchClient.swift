import Foundation
import UIKit
#if canImport(Network)
import Network
#endif

// =====================================================================
//  ZXTouchClient：越狱机触摸模拟的 TCP 客户端
// =====================================================================
//  依赖：设备已安装 zxtouch / SimulateTouch tweak（Cydia 源），
//  它在 127.0.0.1:6000 上监听，协议（layout/usr/lib/python3.7/site-packages/zxtouch/）：
//    消息  = <任务号>;;<参数>;;<参数>\r\n
//    响应  = 0;;<数据>\r\n   （首段非 0 = 失败，第二段是错误信息）
//  任务号（tasktypes.py）：
//    10 TASK_PERFORM_TOUCH   11 TASK_PROCESS_BRING_FOREGROUND
//    13 TASK_RUN_SHELL       24 TASK_KEYBOARDIMPL
//  键盘子任务（kbdtasktypes.py）：1 = INSERT_TEXT（逐字符插入当前输入框）
//  touch 载荷格式（client.py）：
//    '1' + <type 0/1/2 单位> + <finger 2位> + <x*10 5位> + <y*10 5位>
//  iOS 14+ 访问 localhost 需要本地网络权限（Info.plist 的
//  NSLocalNetworkUsageDescription），首次连接会弹窗。
// =====================================================================

public enum ZXTouchError: Error, Equatable {
    /// 服务不可用：没装 tweak / 端口不通 / 本地网络权限被拒
    case unavailable(String)
    /// 设备端返回非 0 状态码
    case protocolError(String)
}

public final class ZXTouchClient {
    public static let shared = ZXTouchClient()

    /// 连接状态（探测用）
    public private(set) var isConnected = false

    private let queue = DispatchQueue(label: "wechatocr.zxtouch")
    private let host = "127.0.0.1"
    private let port: UInt16 = 6000

    #if canImport(Network)
    private var connection: NWConnection?
    #endif

    private init() {}

    // MARK: - 连接

    /// 连接并探测。completion(ok, 人话原因) 回主线程；ok=true 表示可用。
    /// 失败时分两种：.failed（127.0.0.1 上通常是 ECONNREFUSED = tweak 没在监听）
    /// 和超时（权限被卡住时 connect 挂住不返回）——排查动作完全不同，必须分开提示。
    public func connect(timeout: Double = 2.0, completion: @escaping (Bool, String) -> Void) {
        #if canImport(Network)
        if isConnected {
            DispatchQueue.main.async { completion(true, "zxtouch 服务可用（127.0.0.1:6000）") }
            return
        }
        let conn = NWConnection(
            host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!,
            using: .tcp)
        // 只回调一次：failed / cancelled / 超时可能同时来
        var finished = false
        func finish(_ ok: Bool, _ reason: String) {
            guard !finished else { return }
            finished = true
            DispatchQueue.main.async { completion(ok, reason) }
        }
        conn.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.isConnected = true
                finish(true, "zxtouch 服务可用（127.0.0.1:6000）")
            case .failed(let error):
                self?.isConnected = false
                if self?.connection === conn { self?.connection = nil }
                finish(false, "连不上：\(error.localizedDescription)。"
                            + "127.0.0.1:6000 拒绝连接 = zxtouch tweak 没装上或没运行"
                            + "（装完要注销/重启；免费 IPA 不会影响本机回环）")
            case .cancelled:
                self?.isConnected = false
                finish(false, "连接被取消")
            default: break
            }
        }
        connection = conn
        conn.start(queue: queue)
        // 超时兜底：本地网络权限首次弹窗挂起时 connect 会挂住不返回
        queue.asyncAfter(deadline: .now() + timeout) { [weak self] in
            guard let self, !self.isConnected else { return }
            conn.cancel()
            finish(false, "\(Int(timeout)) 秒超时。若系统弹过「是否允许 WeChatOCR 查找并连接"
                        + "本地网络设备」请选允许；再确认 ZXTouch App 在后台运行着，且"
                        + " 设置 → WeChatOCR → 本地网络 为「开」")
        }
        #else
        DispatchQueue.main.async { completion(false, "非 iOS 平台，触摸模拟不可用") }
        #endif
    }

    public func disconnect() {
        #if canImport(Network)
        connection?.cancel()
        connection = nil
        #endif
        isConnected = false
    }

    // MARK: - 触摸

    /// 点击（归一化坐标 0-1）。down 后 80ms up，模拟人手。
    public func tap(nx: Double, ny: Double) {
        let (px, py) = pixels(nx: nx, ny: ny)
        sendTouch(type: 0, x: px, y: py)   // down
        queue.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            self?.sendTouch(type: 2, x: px, y: py)  // up
        }
    }

    /// 长按（备用：某些版本输入框需要长按才弹菜单）
    public func longPress(nx: Double, ny: Double, duration: Double = 0.6) {
        let (px, py) = pixels(nx: nx, ny: ny)
        sendTouch(type: 0, x: px, y: py)
        queue.asyncAfter(deadline: .now() + duration) { [weak self] in
            self?.sendTouch(type: 2, x: px, y: py)
        }
    }

    /// 归一化坐标 → 屏幕像素（点坐标，zxtouch 要的是点不是像素——
    /// client.py 里 x*10 只是为了支持 0.1 精度）
    private func pixels(nx: Double, ny: Double) -> (Int, Int) {
        let size = UIScreen.main.bounds.size
        return (Int((nx * size.width).rounded()), Int((ny * size.height).rounded()))
    }

    /// 发送一个触摸相位。载荷 '1' + type + finger(2) + x*10(5) + y*10(5)
    private func sendTouch(type: Int, x: Int, y: Int) {
        let payload = String(format: "1%d%02d%05d%05d", type, 1, x * 10, y * 10)
        send("10;;\(payload)\r\n", readResponse: false)
    }

    // MARK: - 输入 & 应用切换

    /// 逐字符插入当前聚焦的输入框（中文安全：走 UITextInput 协议，不经输入法）。
    /// completion(totalChars) 或 error。协议分隔符 ;; 和换行会破坏消息，提前拒收。
    public func insertText(_ text: String, completion: @escaping (Result<Int, Error>) -> Void) {
        let chars = Array(text)
        guard !chars.isEmpty else {
            DispatchQueue.main.async { completion(.success(0)) }
            return
        }
        guard !chars.contains(where: { $0 == ";" || $0 == "\r" || $0 == "\n" }) else {
            DispatchQueue.main.async {
                completion(.failure(ZXTouchError.protocolError("回复含分号或换行，请先拆分成多条")))
            }
            return
        }
        insertChar(chars, index: 0, count: 0, completion: completion)
    }

    private func insertChar(_ chars: [Character], index: Int, count: Int,
                            completion: @escaping (Result<Int, Error>) -> Void) {
        guard index < chars.count else {
            DispatchQueue.main.async { completion(.success(count)) }
            return
        }
        // kbdtasktypes.KEYBOARD_INSERT_TEXT = 1
        send("24;;1;;\(chars[index])\r\n") { [weak self] ok, err in
            if !ok {
                DispatchQueue.main.async {
                    completion(.failure(ZXTouchError.protocolError(err)))
                }
                return
            }
            self?.insertChar(chars, index: index + 1, count: count + 1, completion: completion)
        }
    }

    /// 把 App 带到前台（TASK_PROCESS_BRING_FOREGROUND = 11）
    public func switchToApp(_ bundleId: String,
                            completion: @escaping (Bool) -> Void = { _ in }) {
        send("11;;\(bundleId)\r\n") { ok, _ in
            DispatchQueue.main.async { completion(ok) }
        }
    }

    // MARK: - 底层收发

    /// 发一条协议消息。readResponse=false 时不等响应（touch 是即发即忘）。
    private func send(_ message: String, readResponse: Bool = true,
                      completion: ((Bool, String) -> Void)? = nil) {
        #if canImport(Network)
        guard let conn = connection, isConnected else {
            completion?(false, "未连接：请确认已安装 zxtouch 且允许本地网络")
            return
        }
        let data = Data(message.utf8)
        conn.send(content: data, completion: .contentProcessed { [weak self] error in
            if let error {
                self?.isConnected = false
                completion?(false, error.localizedDescription)
                return
            }
            guard readResponse else { completion?(true, ""); return }
            self?.receive(conn) { ok, payload in
                completion?(ok, payload)
            }
        })
        #else
        completion?(false, "非 iOS 平台，触摸模拟不可用")
        #endif
    }

    #if canImport(Network)
    /// 读一条响应：0;;... = 成功；其他 = 失败（第二段是错误信息）
    private func receive(_ conn: NWConnection, completion: @escaping (Bool, String) -> Void) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 1024) { data, _, _, error in
            guard let data, !data.isEmpty, error == nil else {
                completion(false, error?.localizedDescription ?? "空响应")
                return
            }
            let text = String(decoding: data, as: UTF8.self)
            let parts = text.components(separatedBy: "\r\n")[0]
                .components(separatedBy: ";;")
            guard let code = parts.first else {
                completion(false, "响应格式异常")
                return
            }
            if code == "0" {
                completion(true, parts.dropFirst().joined(separator: ";;"))
            } else {
                completion(false, parts.count >= 2 ? parts[1] : "设备端错误 \(code)")
            }
        }
    }
    #endif
}
