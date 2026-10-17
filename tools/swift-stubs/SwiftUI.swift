// =====================================================================
//  SwiftUI 桩模块 —— 仅供 Windows 本地类型检查（preflight）使用。
//
//  设计说明（为什么这么写）：
//   1. View 用「标记协议」——不强制要求 body，任何返回 some View 的
//      结构体都能满足。App 代码里的 var body: some View { ... } 照常工作。
//   2. 修饰符（.font/.foregroundColor/...）统一返回 AnyView（一个
//      通用 View 壳），这样链式调用和后续修饰符都能继续类型检查。
//   3. ViewBuilder 提供 buildBlock(0~10 参) + buildIf + buildEither，
//      覆盖 App 代码里的 if / if-else / 多子视图用法。
//   4. @_exported import UIKit —— 与真机一致：import SwiftUI 后
//      UIImage / UIPasteboard / CGFloat 可见。
// =====================================================================
import Foundation
@_exported import UIKit

// MARK: - 基础协议

public protocol View {}
public protocol Scene {}

// MARK: - 通用 View 壳（修饰符的返回类型）

public struct AnyView: View {
    public init<V: View>(_ view: V) {}
}

public struct EmptyView: View {
    public init() {}
}

public struct TupleView<T>: View {
    public init(_ value: T) {}
}

// MARK: - 结果构建器

@resultBuilder
public struct ViewBuilder {
    public static func buildBlock() -> EmptyView { EmptyView() }

    public static func buildBlock<C1: View>(_ c1: C1) -> C1 { c1 }
    public static func buildBlock<C1: View, C2: View>(_ c1: C1, _ c2: C2)
        -> TupleView<(C1, C2)> { TupleView((c1, c2)) }
    public static func buildBlock<C1: View, C2: View, C3: View>(_ c1: C1, _ c2: C2, _ c3: C3)
        -> TupleView<(C1, C2, C3)> { TupleView((c1, c2, c3)) }
    public static func buildBlock<C1: View, C2: View, C3: View, C4: View>(
        _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4)
        -> TupleView<(C1, C2, C3, C4)> { TupleView((c1, c2, c3, c4)) }
    public static func buildBlock<C1: View, C2: View, C3: View, C4: View, C5: View>(
        _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4, _ c5: C5)
        -> TupleView<(C1, C2, C3, C4, C5)> { TupleView((c1, c2, c3, c4, c5)) }
    public static func buildBlock<C1: View, C2: View, C3: View, C4: View, C5: View,
        C6: View>(_ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4, _ c5: C5, _ c6: C6)
        -> TupleView<(C1, C2, C3, C4, C5, C6)> { TupleView((c1, c2, c3, c4, c5, c6)) }
    public static func buildBlock<C1: View, C2: View, C3: View, C4: View, C5: View,
        C6: View, C7: View>(_ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4, _ c5: C5, _ c6: C6, _ c7: C7)
        -> TupleView<(C1, C2, C3, C4, C5, C6, C7)> { TupleView((c1, c2, c3, c4, c5, c6, c7)) }
    public static func buildBlock<C1: View, C2: View, C3: View, C4: View, C5: View,
        C6: View, C7: View, C8: View>(
        _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4, _ c5: C5, _ c6: C6, _ c7: C7, _ c8: C8)
        -> TupleView<(C1, C2, C3, C4, C5, C6, C7, C8)>
        { TupleView((c1, c2, c3, c4, c5, c6, c7, c8)) }
    public static func buildBlock<C1: View, C2: View, C3: View, C4: View, C5: View,
        C6: View, C7: View, C8: View, C9: View>(
        _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4, _ c5: C5, _ c6: C6, _ c7: C7, _ c8: C8, _ c9: C9)
        -> TupleView<(C1, C2, C3, C4, C5, C6, C7, C8, C9)>
        { TupleView((c1, c2, c3, c4, c5, c6, c7, c8, c9)) }
    public static func buildBlock<C1: View, C2: View, C3: View, C4: View, C5: View,
        C6: View, C7: View, C8: View, C9: View, C10: View>(
        _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4, _ c5: C5, _ c6: C6, _ c7: C7, _ c8: C8,
        _ c9: C9, _ c10: C10)
        -> TupleView<(C1, C2, C3, C4, C5, C6, C7, C8, C9, C10)>
        { TupleView((c1, c2, c3, c4, c5, c6, c7, c8, c9, c10)) }

// if（无 else）——必须包一层 View，Optional<C> 本身不是 View
public static func buildIf<C: View>(_ content: C?) -> _OptionalView<C> {
    _OptionalView(content)
}
    // if / else
    public static func buildEither<C1: View, C2: View>(first: C1) -> _ConditionalContent<C1, C2> {
        _ConditionalContent(first: first)
    }
    public static func buildEither<C1: View, C2: View>(second: C2) -> _ConditionalContent<C1, C2> {
        _ConditionalContent(second: second)
    }
}

public struct _ConditionalContent<C1: View, C2: View>: View {
    public init(first: C1) {}
    public init(second: C2) {}
}

public struct _OptionalView<C: View>: View {
    public init(_ content: C?) {}
}

// MARK: - Binding

@dynamicMemberLookup
public struct Binding<Value> {
    private let getter: () -> Value
    private let setter: (Value) -> Void

    public init(get: @escaping () -> Value, set: @escaping (Value) -> Void) {
        getter = get
        setter = set
    }

    public var wrappedValue: Value {
        get { getter() }
        nonmutating set { setter(newValue) }
    }

    // 关键：$a.b.c 链式动态成员（真实 Binding 也支持）
    public subscript<V>(dynamicMember keyPath: WritableKeyPath<Value, V>) -> Binding<V> {
        Binding<V>(get: { self.wrappedValue[keyPath: keyPath] },
                   set: { self.wrappedValue[keyPath: keyPath] = $0 })
    }
}

// MARK: - 属性包装器

@propertyWrapper
public struct State<Value> {
    // 引用盒 + nonmutating setter：逃逸闭包里也能赋值（真实 SwiftUI 同原理）
    private final class Box {
        var value: Value
        init(_ value: Value) { self.value = value }
    }
    private let box: Box

    public var wrappedValue: Value {
        get { box.value }
        nonmutating set { box.value = newValue }
    }

    public init(wrappedValue thunk: @autoclosure @escaping () -> Value) {
        box = Box(thunk())
    }

    public var projectedValue: Binding<Value> {
        Binding(get: { box.value }, set: { box.value = $0 })
    }
}

@propertyWrapper
public struct ObservedObject<Value: ObservableObject> {
    public var wrappedValue: Value

    public init(wrappedValue: Value) {
        self.wrappedValue = wrappedValue
    }

    public var projectedValue: Wrapper { Wrapper() }

    // $obj.member 链式动态成员（与真实 SwiftUI 一致）
    @dynamicMemberLookup
    public struct Wrapper {
        public subscript<V>(dynamicMember keyPath: WritableKeyPath<Value, V>) -> Binding<V> {
            Binding(get: { fatalError() }, set: { _ in })
        }
    }
}

@propertyWrapper
public struct StateObject<Value: ObservableObject> {
    public var wrappedValue: Value

    public init(wrappedValue thunk: @autoclosure @escaping () -> Value) {
        wrappedValue = thunk()
    }

    public var projectedValue: Binding<Value> {
        Binding(get: { fatalError() }, set: { _ in })
    }
}

@propertyWrapper
public struct EnvironmentObject<Value: ObservableObject> {
    public var wrappedValue: Value
    public init(wrappedValue: Value) { self.wrappedValue = wrappedValue }
}

// MARK: - 基础控件

public struct Text: View {
    public init(_ content: String) {}
    public init(_ date: Date, style: Text.DateStyle) {}

    public struct DateStyle {
        public static let time = DateStyle()
        public static let date = DateStyle()
        public static let relative = DateStyle()
        public static let offset = DateStyle()
        public static let timer = DateStyle()
    }
}

public struct Image: View {
    public init(systemName: String) {}
    public init(_ name: String) {}
}

// App 代码只用到「字符串标题 + systemImage」这一种 Label
public struct Label: View {
    public init(_ title: String, systemImage: String) {}
}

public struct LabeledContent: View {
    public init(_ title: String, value: String) {}
}

public struct ProgressView: View {
    public init() {}
}

// MARK: - 容器

public struct TabView<Content: View>: View {
    public init(@ViewBuilder content: () -> Content) {}
}

public struct NavigationStack<Content: View>: View {
    public init(@ViewBuilder content: () -> Content) {}
}

public struct List<Content: View>: View {
    public init(@ViewBuilder content: () -> Content) {}
}

public struct Form<Content: View>: View {
    public init(@ViewBuilder content: () -> Content) {}
}

public struct HStack<Content: View>: View {
    public init(alignment: Alignment = .center, spacing: CGFloat? = nil,
                @ViewBuilder content: () -> Content) {}
}

public struct VStack<Content: View>: View {
    public init(alignment: Alignment = .center, spacing: CGFloat? = nil,
                @ViewBuilder content: () -> Content) {}
}

public struct ZStack<Content: View>: View {
    public init(alignment: Alignment = .center, @ViewBuilder content: () -> Content) {}
}

public struct Spacer: View {
    public init(minLength: CGFloat? = nil) {}
}

// 一个结构体 + 约束扩展（真实 SwiftUI 的 Section 就是这样声明的）
public struct Section<Header: View, Content: View, Footer: View>: View {
    public init(header: () -> Header, @ViewBuilder content: () -> Content,
                @ViewBuilder footer: () -> Footer) {}
    /// `Section { } header: { } footer: { }` 形式
    public init(@ViewBuilder content: () -> Content,
                @ViewBuilder header: () -> Header,
                @ViewBuilder footer: () -> Footer) {}
}

extension Section where Header == Never, Footer == Never {
    public init(@ViewBuilder content: () -> Content) {}
    public init(_ title: String, @ViewBuilder content: () -> Content) {}
}

extension Section where Header == Never {
    public init(@ViewBuilder content: () -> Content, @ViewBuilder footer: () -> Footer) {}
    public init(_ title: String, @ViewBuilder content: () -> Content,
                @ViewBuilder footer: () -> Footer) {}
}

extension Never: View {}

// 两个 init 共用一个结构体（真实 SwiftUI 也是这样：struct 只声明一次，
// 不同约束放在各 init 的 where 从句上）
public struct ForEach<Data: RandomAccessCollection, ID: Hashable, Content: View>: View {
    // 元素自身 Identifiable：id 可省略（ID 固定为 Data.Element.ID）
    public init(_ data: Data, @ViewBuilder content: @escaping (Data.Element) -> Content)
        where Data.Element: Identifiable, ID == Data.Element.ID {}

    // 显式指定 id KeyPath
    public init(_ data: Data, id: KeyPath<Data.Element, ID>,
                @ViewBuilder content: @escaping (Data.Element) -> Content) {}
}

// MARK: - 输入控件

public struct Button<Label: View>: View {
    public init(action: @escaping () -> Void, @ViewBuilder label: () -> Label) {}
}

// 字符串标题构造器（Label 固定为 Text）——真实 SwiftUI 也是这样分声明的
extension Button where Label == Text {
    public init(_ title: String, role: ButtonRole? = nil, action: @escaping () -> Void) {}
}

public enum ButtonRole {
    case destructive
    case cancel
}

public struct TextField: View {
    public init(_ title: String, text: Binding<String>) {}
}

public struct SecureField: View {
    public init(_ title: String, text: Binding<String>) {}
}

public struct TextEditor: View {
    public init(text: Binding<String>) {}
}

public struct Picker<Selection: Hashable, Content: View>: View {
    public init(_ title: String, selection: Binding<Selection>,
                @ViewBuilder content: () -> Content) {}
}

public struct Toggle: View {
    public init(_ title: String, isOn: Binding<Bool>) {}
}

public struct Stepper: View {
    public init(_ title: String, value: Binding<Int>, in: ClosedRange<Int>) {}
    public init(_ title: String, value: Binding<Double>, in: ClosedRange<Double>,
                step: Double = 1) {}
}

// MARK: - 颜色 / 形状样式

public protocol ShapeStyle {}

// 必须有 Self 约束，否则 .secondary 这种上下文成员查找会失败
// （真实 SwiftUI 也是 extension ShapeStyle where Self == HierarchicalShapeStyle）
extension ShapeStyle where Self == HierarchicalShapeStyle {
    public static var secondary: HierarchicalShapeStyle { HierarchicalShapeStyle() }
    public static var primary: HierarchicalShapeStyle { HierarchicalShapeStyle() }
    public static var tertiary: HierarchicalShapeStyle { HierarchicalShapeStyle() }
    public static var quaternary: HierarchicalShapeStyle { HierarchicalShapeStyle() }
}

// .orange / .green / .blue 等颜色成员（真实 SwiftUI 同样以 Self == Color 约束声明）
// 注意：primary / secondary 只属于 HierarchicalShapeStyle，不放在这里，否则二义
extension ShapeStyle where Self == Color {
    public static var red: Color { Color() }
    public static var orange: Color { Color() }
    public static var yellow: Color { Color() }
    public static var green: Color { Color() }
    public static var mint: Color { Color() }
    public static var teal: Color { Color() }
    public static var blue: Color { Color() }
    public static var purple: Color { Color() }
    public static var pink: Color { Color() }
    public static var gray: Color { Color() }
    public static var black: Color { Color() }
    public static var white: Color { Color() }
}

public struct HierarchicalShapeStyle: ShapeStyle {}

public struct Color: ShapeStyle, View {
    public static let red = Color()
    public static let orange = Color()
    public static let yellow = Color()
    public static let green = Color()
    public static let mint = Color()
    public static let teal = Color()
    public static let blue = Color()
    public static let purple = Color()
    public static let pink = Color()
    public static let gray = Color()
    public static let black = Color()
    public static let white = Color()
    public static let primary = Color()
    public static let secondary = Color()

    public func opacity(_ opacity: Double) -> Color { self }
}

// MARK: - 字体 / 对齐 / 边距

public struct Font {
    public static let largeTitle = Font()
    public static let title = Font()
    public static let title2 = Font()
    public static let title3 = Font()
    public static let headline = Font()
    public static let subheadline = Font()
    public static let body = Font()
    public static let callout = Font()
    public static let footnote = Font()
    public static let caption = Font()
    public static let caption2 = Font()
}

public struct Alignment {
    public static let leading = Alignment()
    public static let trailing = Alignment()
    public static let top = Alignment()
    public static let bottom = Alignment()
    public static let center = Alignment()
    public static let topLeading = Alignment()
    public static let topTrailing = Alignment()
    public static let bottomLeading = Alignment()
    public static let bottomTrailing = Alignment()
}

public struct Edge {
    public struct Set: OptionSet {
        public var rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let top = Set(rawValue: 1)
        public static let leading = Set(rawValue: 2)
        public static let bottom = Set(rawValue: 4)
        public static let trailing = Set(rawValue: 8)
        public static let all = Set(rawValue: 15)
        public static let horizontal = Set(rawValue: 10)
        public static let vertical = Set(rawValue: 5)
    }
}

public enum TextSelection {
    case enabled
    case disabled
}

public enum TextInputAutocapitalization {
    case never
    case words
    case sentences
    case characters
}

public enum ControlSize {
    case mini
    case small
    case regular
    case large
}

// MARK: - 样式协议

public protocol ButtonStyle {}
public protocol PickerStyle {}

// 和 ShapeStyle 一样：静态成员要放在 Self == 具体类型 的约束扩展里，
// 否则 .buttonStyle(.borderless) 这种上下文查找会失败。
// （真实 SwiftUI 就是这样声明的）
extension ButtonStyle where Self == BorderlessButtonStyle {
    public static var borderless: BorderlessButtonStyle { BorderlessButtonStyle() }
}
extension ButtonStyle where Self == BorderedButtonStyle {
    public static var bordered: BorderedButtonStyle { BorderedButtonStyle() }
}
extension ButtonStyle where Self == BorderedProminentButtonStyle {
    public static var borderedProminent: BorderedProminentButtonStyle {
        BorderedProminentButtonStyle()
    }
}
extension ButtonStyle where Self == PlainButtonStyle {
    public static var plain: PlainButtonStyle { PlainButtonStyle() }
}
extension PickerStyle where Self == MenuPickerStyle {
    public static var menu: MenuPickerStyle { MenuPickerStyle() }
}
extension PickerStyle where Self == InlinePickerStyle {
    public static var inline: InlinePickerStyle { InlinePickerStyle() }
}

public struct BorderlessButtonStyle: ButtonStyle {
    public static let borderless = BorderlessButtonStyle()
}
public struct BorderedButtonStyle: ButtonStyle {
    public static let bordered = BorderedButtonStyle()
}
public struct BorderedProminentButtonStyle: ButtonStyle {
    public static let borderedProminent = BorderedProminentButtonStyle()
}
public struct PlainButtonStyle: ButtonStyle {
    public static let plain = PlainButtonStyle()
}
public struct MenuPickerStyle: PickerStyle {
    public static let menu = MenuPickerStyle()
}
public struct InlinePickerStyle: PickerStyle {
    public static let inline = InlinePickerStyle()
}

// MARK: - 工具栏

public struct ToolbarItemPlacement {
    public static let navigationBarLeading = ToolbarItemPlacement()
    public static let navigationBarTrailing = ToolbarItemPlacement()
    public static let bottomBar = ToolbarItemPlacement()
    public static let automatic = ToolbarItemPlacement()
}

public struct ToolbarItem<Content: View>: View {
    public init(placement: ToolbarItemPlacement, @ViewBuilder content: () -> Content) {}
}

public struct ToolbarItemGroup<Content: View>: View {
    public init(placement: ToolbarItemPlacement, @ViewBuilder content: () -> Content) {}
}

// MARK: - 场景 / App

public struct WindowGroup<Content: View>: Scene {
    public init(@ViewBuilder content: () -> Content) {}
}

public protocol App {
    associatedtype Body: Scene
    var body: Body { get }
}

extension App {
    public static func main() {}
}

// MARK: - 修饰符

extension View {
    public func font(_ font: Font?) -> AnyView { AnyView(self) }
    public func foregroundColor<S: ShapeStyle>(_ style: S) -> AnyView { AnyView(self) }
    public func disabled(_ disabled: Bool) -> AnyView { AnyView(self) }
    public func frame(width: CGFloat? = nil, height: CGFloat? = nil,
                      alignment: Alignment = .center) -> AnyView { AnyView(self) }
    public func frame(maxWidth: CGFloat? = nil, maxHeight: CGFloat? = nil,
                      alignment: Alignment = .center) -> AnyView { AnyView(self) }
    public func frame(minWidth: CGFloat? = nil, minHeight: CGFloat? = nil,
                      alignment: Alignment = .center) -> AnyView { AnyView(self) }
    public func padding(_ edges: Edge.Set = .all, _ length: CGFloat? = nil) -> AnyView {
        AnyView(self)
    }
    public func cornerRadius(_ radius: CGFloat) -> AnyView { AnyView(self) }
    public func background<S: ShapeStyle>(_ style: S,
                                          alignment: Alignment = .center) -> AnyView {
        AnyView(self)
    }
    public func opacity(_ opacity: Double) -> AnyView { AnyView(self) }
    public func textSelection(_ selection: TextSelection) -> AnyView { AnyView(self) }
    public func buttonStyle<S: ButtonStyle>(_ style: S) -> AnyView { AnyView(self) }
    public func controlSize(_ size: ControlSize) -> AnyView { AnyView(self) }
    public func pickerStyle<S: PickerStyle>(_ style: S) -> AnyView { AnyView(self) }
    public func keyboardType(_ type: UIKeyboardType) -> AnyView { AnyView(self) }
    public func textInputAutocapitalization(_ value: TextInputAutocapitalization?) -> AnyView {
        AnyView(self)
    }
    public func autocorrectionDisabled(_ disabled: Bool = true) -> AnyView { AnyView(self) }
    public func navigationTitle(_ title: String) -> AnyView { AnyView(self) }
    public func tabItem<Content: View>(@ViewBuilder content: () -> Content) -> AnyView {
        AnyView(self)
    }
    public func toolbar<Content: View>(@ViewBuilder content: () -> Content) -> AnyView {
        AnyView(self)
    }
    public func foregroundStyle<S: ShapeStyle>(_ style: S) -> AnyView { AnyView(self) }
    public func onTapGesture(count: Int = 1, perform: @escaping () -> Void) -> AnyView {
        AnyView(self)
    }
    // 注意：带 coordinateSpace 的重载是 iOS 17.0+ 才有的（部署目标 16.0 不能用），
    // 拿不准最低版本时务必查 Apple 文档——桩无法替你检查可用性。
    @available(iOS 17.0, macOS 14.0, *)
    public func onTapGesture(count: Int = 1, coordinateSpace: CoordinateSpace,
                             perform: @escaping (CGPoint) -> Void) -> AnyView {
        AnyView(self)
    }
    public func contentShape<S: Shape>(_ shape: S) -> AnyView { AnyView(self) }
    public func sheet<Content: View>(isPresented: Binding<Bool>,
                                     @ViewBuilder content: @escaping () -> Content) -> AnyView {
        AnyView(self)
    }
    public func fullScreenCover<Content: View>(isPresented: Binding<Bool>,
                                               @ViewBuilder content: @escaping () -> Content) -> AnyView {
        AnyView(self)
    }
    public func interactiveDismissDisabled(_ disabled: Bool = true) -> AnyView { AnyView(self) }
    public func presentationDetents(_ detents: Set<PresentationDetent>) -> AnyView { AnyView(self) }
    public func listRowSeparator(_ visibility: Visibility) -> AnyView { AnyView(self) }
    public func scrollDismissesKeyboard(_ mode: ScrollDismissesKeyboardMode) -> AnyView {
        AnyView(self)
    }
    public func tag<V>(_ tag: V) -> AnyView { AnyView(self) }
    public func onChange<V: Equatable>(of value: V, _ action: @escaping (V) -> Void) -> AnyView {
        AnyView(self)
    }
    public func onChange<V: Equatable>(of value: V, initial: Bool = false,
                                       _ action: @escaping () -> Void) -> AnyView {
        AnyView(self)
    }
}

// MARK: - 布局与手势辅助（校准页用）

public struct GeometryProxy {
    public var size: CGSize { CGSize(width: 390, height: 844) }
    public func frame(in coordinateSpace: CoordinateSpace) -> CGRect {
        CGRect(origin: .zero, size: size)
    }
}

public struct GeometryReader<Content: View>: View {
    private let content: (GeometryProxy) -> Content
    public init(@ViewBuilder content: @escaping (GeometryProxy) -> Content) {
        self.content = content
    }
}

public struct CoordinateSpace {
    public static let global = CoordinateSpace()
    public static let local = CoordinateSpace()
    public init() {}
}

public enum ScrollDismissesKeyboardMode { case automatic, never, always }
public enum Visibility { case automatic, visible, hidden }
public struct PresentationDetent { public static let medium = PresentationDetent() }
public enum NavigationBarItemTitleDisplayMode { case automatic, inline, large }
public enum NavigationBarTitleDisplayMode { case automatic, inline, large }

// MARK: - Environment（dismiss 用）

public struct DismissAction {
    public func callAsFunction() {}
}

public struct EnvironmentValues {
    public var dismiss: DismissAction { DismissAction() }
}

@propertyWrapper
public struct Environment<Value> {
    public var wrappedValue: Value
    public init(_ keyPath: KeyPath<EnvironmentValues, Value>) {
        wrappedValue = EnvironmentValues()[keyPath: keyPath]
    }
}

// contentShape 的 Shape 约束 + PresentationDetent 的 Hashable（校准页修饰符需要）
public protocol Shape {}

extension PresentationDetent: Hashable {
    public static func == (lhs: PresentationDetent, rhs: PresentationDetent) -> Bool { true }
    public func hash(into hasher: inout Hasher) {}
}

// MARK: - 形状（校准页用）

public struct Rectangle: Shape { public init() {} }
public struct RoundedRectangle: Shape {
    public var cornerRadius: CGFloat
    public init(cornerRadius: CGFloat) { self.cornerRadius = cornerRadius }
    public init(cornerSize: CGSize) { cornerRadius = cornerSize.width }
}

extension Color {
    public func ignoresSafeArea(_ edges: Edge.Set = .all) -> AnyView { AnyView(self) }
}

extension Text {
    public func multilineTextAlignment(_ alignment: TextAlignment) -> AnyView { AnyView(self) }
}

public enum TextAlignment { case leading, center, trailing }

// Text 专属修饰符（优先于 View 扩展，避免 AnyView 丢掉 Text 类型）
extension Text {
    public func font(_ font: Font?) -> Text { self }
    public func foregroundColor<S: ShapeStyle>(_ style: S) -> Text { self }
    public func foregroundStyle<S: ShapeStyle>(_ style: S) -> Text { self }
    public func bold() -> Text { self }
}

// MARK: - 手势（校准页：DragGesture 取点击位置，iOS 13+ 通用写法）
//
// 为什么不用 onTapGesture(coordinateSpace:perform:)：那是 iOS 17+ API，
// 工程部署目标是 16.0，用了直接编译报错。DragGesture(minimumDistance: 0)
// 从 iOS 13 起可用，onEnded 里拿 value.location，行为等价。

public protocol Gesture {
    associatedtype Value
}

extension Gesture {
    public func onEnded(perform action: @escaping (Value) -> Void) -> Self { self }
}

public struct DragGestureValue {
    public var location: CGPoint
    public var startLocation: CGPoint
    public var translation: CGSize
    public init() {
        location = .zero
        startLocation = .zero
        translation = .zero
    }
}

public struct DragGesture: Gesture {
    public typealias Value = DragGestureValue
    public init(minimumDistance: CGFloat = 0, coordinateSpace: CoordinateSpace = .local) {}
}

// .gesture(_:) 修饰符（真实签名：func gesture<T: Gesture>(_ gesture: T, including: GestureMask = .all)）
public enum GestureMask { case all, subviews, never }

extension View {
    public func gesture<T: Gesture>(_ gesture: T,
                                    including mask: GestureMask = .all) -> AnyView {
        AnyView(self)
    }
}
