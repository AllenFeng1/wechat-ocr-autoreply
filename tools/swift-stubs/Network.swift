// Network 框架桩（仅复刻 ZXTouchClient.swift 实际用到的 API 形状）
//
// 为什么需要它：ZXTouchClient 的 TCP 实现整段包在 #if canImport(Network) 里，
// Windows 上没有 Network 模块 → 预检时整段被跳过 → iOS 独有的编译错误
// （如 NWConnection(host:port:uses:) 写错参数名）本地发现不了，只能靠 CI 翻车。
// 有了这个桩，canImport(Network) 在预检时为真，这段代码就被完整类型检查。
//
// 签名对照 Apple 官方文档（iOS 12+）逐条核对：
//   convenience init(host: NWEndpoint.Host, port: NWEndpoint.Port, using: NWParameters)
//   init(to: NWEndpoint, using: NWParameters)
//   func start(queue: DispatchQueue)
//   var stateUpdateHandler: ((NWConnection.State) -> Void)?
//   func send(_ content: Data?, contentContext: NWConnection.ContentContext = .defaultMessage,
//             isComplete: Bool = true, completion: NWConnection.SendCompletion = .contentProcessed)
//   func receive(minimumIncompleteLength: Int, maximumLength: Int,
//                completion: (Data?, NWConnection.ContentContext?, Bool, NWError?) -> Void)
//   func cancel()
import Foundation

public final class NWEndpoint {
    public struct Host: Equatable, Hashable {
        public var debugDescription: String
        public init(_ string: String) { debugDescription = string }
    }

    public struct Port: RawRepresentable, Equatable, Hashable {
        public var rawValue: UInt16
        public init?(rawValue: UInt16) { self.rawValue = rawValue }
    }
}

open class NWParameters {
    public static let tcp = NWParameters()
    public static let udp = NWParameters()
    public init() {}
}

public struct NWError: Error, Equatable {
    public init() {}
}

public final class NWConnection {
    public enum State: Equatable {
        case setup, waiting, preparing, ready, failed, cancelled, invalid
    }

    public enum SendCompletion {
        case contentProcessed((Error?) -> Void)
        case idempotent
    }

    public class ContentContext {
        public static let defaultMessage = ContentContext()
        public init() {}
    }

    private init() {}

    public convenience init(host: NWEndpoint.Host, port: NWEndpoint.Port, using: NWParameters) {
        self.init()
    }

    public convenience init(to: NWEndpoint, using: NWParameters) {
        self.init()
    }

    public var stateUpdateHandler: ((NWConnection.State) -> Void)?

    public func start(queue: DispatchQueue) {}

    public func cancel() {}

    public func send(_ content: Data?,
                     contentContext: NWConnection.ContentContext = .defaultMessage,
                     isComplete: Bool = true,
                     completion: NWConnection.SendCompletion) {}

    public func receive(minimumIncompleteLength: Int, maximumLength: Int,
                        completion: (Data?, NWConnection.ContentContext?, Bool, NWError?) -> Void) {}
}
