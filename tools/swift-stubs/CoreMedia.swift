// =====================================================================
//  CoreMedia 桩模块 —— 仅供 Windows 本地类型检查（preflight）使用
// =====================================================================

public class CVPixelBuffer {}

public class CMSampleBuffer {}

public func CMSampleBufferGetImageBuffer(_ sampleBuffer: CMSampleBuffer?) -> CVPixelBuffer? {
    nil
}
