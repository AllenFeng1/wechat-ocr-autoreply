// =====================================================================
//  CoreImage 桩模块 —— 仅供 Windows 本地类型检查（preflight）使用。
// =====================================================================
import Foundation
@_exported import CoreGraphics
@_exported import CoreMedia

public final class CIContext {
    public struct Options: Hashable {
        public static let useSoftwareRenderer = Options()
        public static let cacheIntermediates = Options()
        public static let name = Options()
    }

    public init(options: [Options: Any]? = nil) {}
    public func createCGImage(_ image: CIImage, from fromRect: CGRect) -> CGImage? { nil }
}

public final class CIImage {
    public var extent: CGRect = .zero
    public init(cvPixelBuffer: CVPixelBuffer) {}
    public func transformed(by matrix: CGAffineTransform) -> CIImage { self }
}
