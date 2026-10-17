// =====================================================================
//  Combine 桩模块（只含 @Published / ObservableObject）
//  仅供 Windows 本地类型检查（preflight）使用。
//  iOS 上 @Published 经 UIKit 透出；Windows corelibs Foundation 没有，
//  所以 UIKit 桩 @_exported import 本模块来保持同一可见性。
// =====================================================================

public protocol ObservableObject: AnyObject {}

@propertyWrapper
public struct Published<Value> {
    public var wrappedValue: Value

    public init(wrappedValue: Value) {
        self.wrappedValue = wrappedValue
    }

    public struct Publisher {}
    public var projectedValue: Publisher { Publisher() }
}
