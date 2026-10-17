// =====================================================================
//  os 桩模块（Logger / os_log）—— 仅供 Windows 本地类型检查使用。
//  关键点：字符串插值的 appendInterpolation 必须带
//  @autoclosure @escaping —— 真实签名就是这样，
//  只有这样本地才能复现「插值里访问 self 属性必须显式 self.」这一类错误。
// =====================================================================

public struct OSLogType: Equatable {
    public static let `default` = OSLogType()
    public static let info     = OSLogType()
    public static let debug    = OSLogType()
    public static let error    = OSLogType()
    public static let fault    = OSLogType()
}

public enum OSLogPrivacy {
    case `public`
    case `private`
    case sensitive
    case auto
}

public struct OSLog: Equatable {
    public init() {}
    public init(subsystem: String, category: String) {}
    public static let `default` = OSLog()
}

public struct OSLogMessage: ExpressibleByStringInterpolation, ExpressibleByStringLiteral {
    public init(stringInterpolation: Interpolation) {}
    public init(stringLiteral value: String) {}

    public struct Interpolation: StringInterpolationProtocol {
        public init(literalCapacity: Int, interpolationCount: Int) {}

        public mutating func appendLiteral(_ literal: String) {}

        // 带 privacy 的重载（App 代码实际使用的两种）
        public mutating func appendInterpolation(_ value: @autoclosure @escaping () -> String,
                                                 privacy: OSLogPrivacy) {}
        public mutating func appendInterpolation(_ value: @autoclosure @escaping () -> Int,
                                                 privacy: OSLogPrivacy) {}

        // 不带 privacy 的重载
        public mutating func appendInterpolation(_ value: String) {}
        public mutating func appendInterpolation(_ value: Int) {}
        public mutating func appendInterpolation(_ value: @autoclosure @escaping () -> String) {}
        public mutating func appendInterpolation(_ value: @autoclosure @escaping () -> Int) {}
    }
}

public func os_log(_ type: OSLogType, _ message: OSLogMessage, log: OSLog = .default) {}
public func os_log(_ message: OSLogMessage, log: OSLog = .default, type: OSLogType = .default) {}

public struct Logger {
    public init() {}
    public init(subsystem: String, category: String) {}

    public func error(_ message: OSLogMessage) {}
    public func info(_ message: OSLogMessage) {}
    public func debug(_ message: OSLogMessage) {}
    public func fault(_ message: OSLogMessage) {}
}
