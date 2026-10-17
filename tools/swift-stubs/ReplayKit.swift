// =====================================================================
//  ReplayKit 桩模块 —— 仅供 Windows 本地类型检查（preflight）使用。
// =====================================================================
import Foundation
@_exported import CoreMedia

public struct RPSampleBufferType: Equatable, RawRepresentable {
    public var rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }

    public static let video      = RPSampleBufferType(rawValue: 1)
    public static let audioApp   = RPSampleBufferType(rawValue: 2)
    public static let microphone = RPSampleBufferType(rawValue: 3)
}

open class RPBroadcastSampleHandler {
    public init() {}

    open func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {}
    open func broadcastPaused() {}
    open func broadcastResumed() {}
    open func broadcastFinished() {}
    open func processSampleBuffer(_ sampleBuffer: CMSampleBuffer,
                                  with sampleBufferType: RPSampleBufferType) {}
}
