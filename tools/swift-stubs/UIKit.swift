// =====================================================================
//  UIKit 桩模块 —— 仅供 Windows 本地类型检查（preflight）使用。
//  只复刻 App 代码实际用到的 API：
//    UIImage / UIPasteboard / UIApplication / UIKeyboardType
//  并 @_exported 透出 CoreGraphics 与 Combine（与真机行为一致：
//  import UIKit 后即可见 CGFloat/CGRect 和 @Published）。
// =====================================================================
@_exported import Foundation
@_exported import CoreGraphics
@_exported import Combine

public final class UIImage {
    public var size: CGSize = .zero
    public var cgImage: CGImage?
    public var scale: CGFloat = 1

    public init?(data: Data) { nil }
    public init?(cgImage: CGImage, scale: CGFloat, orientation: Orientation) {
        self.cgImage = cgImage
        self.scale = scale
    }

    public enum Orientation: Int {
        case up = 0
        case down = 1
        case left = 2
        case right = 3
    }
}

public final class UIPasteboard {
    public static let general = UIPasteboard()

    public struct Name: RawRepresentable, Hashable, Equatable {
        public var rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public static let general = Name(rawValue: "general")
    }

    public init() {}
    public init?(name: Name, create: Bool) { nil }

    public var string: String?
    public var strings: [String]?

    public func setData(_ data: Data, forPasteboardType pasteboardType: String) {}
    public func data(forPasteboardType pasteboardType: String) -> Data? { nil }
}

public final class UIApplication {
    public static let shared = UIApplication()
    public init() {}
    public func canOpenURL(_ url: URL) -> Bool { false }
    public func open(_ url: URL) {}
}

public final class UIScreen {
    public static let main = UIScreen()
    public init() {}
    public var bounds: CGRect { CGRect(x: 0, y: 0, width: 390, height: 844) }
}

public enum UIKeyboardType: Int {
    case `default`
    case asciiCapable
    case numbersAndPunctuation
    case URL
    case numberPad
    case phonePad
    case namePhonePad
    case emailAddress
    case decimalPad
    case twitter
    case webSearch
    case asciiCapableNumberPad
}

// autoreleasepool 在 iOS 上由 Foundation 提供（import UIKit 即可见）；
// Windows corelibs Foundation 没有，补一个同形状的全局函数。
public func autoreleasepool<Result>(_ body: () throws -> Result) rethrows -> Result {
    try body()
}
