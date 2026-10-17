// =====================================================================
//  CoreGraphics 桩模块 —— 仅供 Windows 本地类型检查（preflight）使用。
//
//  注意：CGFloat / CGPoint / CGSize / CGRect 在 Windows corelibs
//  Foundation 里已经有完整实现（minX/maxX/midX/.zero 等都支持），
//  这里不再重复声明（重复会撞名导致 ambiguous）。
//  本模块只补 Foundation 没有的 CoreGraphics 类型。
// =====================================================================
import Foundation

public struct CGAffineTransform: Equatable {
    public var a: CGFloat, b: CGFloat, c: CGFloat, d: CGFloat, tx: CGFloat, ty: CGFloat
    public init(a: CGFloat, b: CGFloat, c: CGFloat, d: CGFloat, tx: CGFloat, ty: CGFloat) {
        self.a = a; self.b = b; self.c = c; self.d = d; self.tx = tx; self.ty = ty
    }
    public init(scaleX: CGFloat, y: CGFloat) {
        self.init(a: scaleX, b: 0, c: 0, d: y, tx: 0, ty: 0)
    }
    public static let identity = CGAffineTransform(a: 1, b: 0, c: 0, d: 1, tx: 0, ty: 0)
}

public struct CGBitmapInfo: OptionSet {
    public var rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }

    public static let byteOrder16Little = CGBitmapInfo(rawValue: 1 << 12)
    public static let byteOrder16Big    = CGBitmapInfo(rawValue: 2 << 12)
    public static let byteOrder32Little = CGBitmapInfo(rawValue: 3 << 12)
    public static let byteOrder32Big    = CGBitmapInfo(rawValue: 4 << 12)
}

public struct CGImageAlphaInfo: OptionSet {
    public var rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }

    public static var none: CGImageAlphaInfo { CGImageAlphaInfo(rawValue: 0) }
    public static let premultipliedFirst = CGImageAlphaInfo(rawValue: 1)
    public static let premultipliedLast  = CGImageAlphaInfo(rawValue: 2)
}

public typealias CFString = String

public struct CGColorSpace {
    public static let sRGB: CFString = "kCGColorSpaceSRGB"
    public init?(name: CFString) {}
}

public struct CGContext {
    public init?(data: UnsafeMutableRawPointer?, width: Int, height: Int,
                 bitsPerComponent: Int, bytesPerRow: Int, space: CGColorSpace,
                 bitmapInfo: UInt32) {}
    public func draw(_ image: CGImage, in: CGRect) {}
    public func makeImage() -> CGImage? { nil }
}

public struct CGDataProvider {
    public var data: CFData?
}

// CFData 在 iOS 上由 CoreFoundation 提供（Foundation 自带）；
// Windows corelibs Foundation 没有，这里补一个同形状的桩。
// 注意：真实签名返回 UnsafePointer<UInt8>!（隐式解包可选），
// App 代码用 guard let 解它，桩必须保持可选。
public struct CFData {}

public func CFDataGetBytePtr(_ data: CFData) -> UnsafePointer<UInt8>? {
    nil
}

public struct CGImage {
    public var width: Int = 0
    public var height: Int = 0
    public var bitsPerPixel: Int = 32
    public var bytesPerRow: Int = 0
    public var bitmapInfo: CGBitmapInfo = []
    public var dataProvider: CGDataProvider?
    public init() {}
}
