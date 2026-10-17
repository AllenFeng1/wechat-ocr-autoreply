// =====================================================================
//  PhotosUI 桩模块 —— 仅供 Windows 本地类型检查（preflight）使用。
//  注意 loadTransferable 的真实签名返回 T?（可选）——
//  桩必须保持一致，否则漏掉「try? 之后是 T??」这类真实编译错误。
// =====================================================================
import Foundation
import SwiftUI

public protocol Transferable {}

extension Data: Transferable {}

public struct PhotosPickerItem: Equatable {
    public func loadTransferable<T: Transferable>(type: T.Type) async throws -> T? {
        nil
    }
}

public struct PHPickerConfiguration {
    public struct Filter {
        public static let images = Filter()
        public static let videos = Filter()
        public static let livePhotos = Filter()
        public static let anyOf = Filter()
        public static let all = Filter()
    }

    public struct PhotoLibrary {
        public static func shared() -> PhotoLibrary { PhotoLibrary() }
    }
}

public struct PhotosPicker<Label: View>: View {
    public init(selection: Binding<PhotosPickerItem?>,
                matching: PHPickerConfiguration.Filter? = nil,
                photoLibrary: PHPickerConfiguration.PhotoLibrary = .shared(),
                @ViewBuilder label: () -> Label) {}
}
