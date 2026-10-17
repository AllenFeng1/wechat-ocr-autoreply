// =====================================================================
//  Vision 桩模块 —— 仅供 Windows 本地类型检查（preflight）使用。
//  复刻 OCRPipeline 用到的 API：VNRecognizeTextRequest /
//  VNRecognizedTextObservation / VNImageRequestHandler。
// =====================================================================
import Foundation
@_exported import CoreGraphics
@_exported import CoreMedia

public enum VNRequestTextRecognitionLevel {
    case accurate
    case fast
}

// ImageIO 的类型，真实环境经 Vision 透出
public enum CGImagePropertyOrientation {
    case up
    case down
    case left
    case right
    case upMirrored
    case downMirrored
    case leftMirrored
    case rightMirrored
}

public struct VNImageOption: Hashable {
    public static let ciContext = VNImageOption()
}

open class VNRequest {
    public init() {}
}

public final class VNRecognizeTextRequest: VNRequest {
    public override init() {}

    public var recognitionLevel: VNRequestTextRecognitionLevel = .fast
    public var recognitionLanguages: [String] = []
    public var usesLanguageCorrection = true
    public var customWords: [String] = []
    public var minimumTextHeight: Float = 0.0

    // 注意：真实 API 在子类里把 results 收窄成具体元素类型
    public var results: [VNRecognizedTextObservation]?
}

public final class VNRecognizedTextObservation {
    public var boundingBox: CGRect = .zero
    public func topCandidates(_ maxResults: Int) -> [VNRecognizedText] { [] }
}

public final class VNRecognizedText {
    public var string: String = ""
}

public final class VNImageRequestHandler {
    public init(cvPixelBuffer: CVPixelBuffer, options: [VNImageOption: Any] = [:]) {}
    public init(cgImage: CGImage, orientation: CGImagePropertyOrientation,
                options: [VNImageOption: Any] = [:]) {}
    public func perform(_ requests: [VNRequest]) throws {}
}
