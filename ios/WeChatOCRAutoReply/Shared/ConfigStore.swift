import Foundation

/// App Group UserDefaults：主 App 写配置，录屏扩展读配置。
/// 注意：App Group 需要付费 Apple 开发者账号；未配置时回退到各自进程的
/// standard defaults（扩展将使用默认配置运行，主 App 的修改不会同步）。
public enum ConfigStore {
    public static let appGroupSuite = "group.com.allenfeng1.wechatocr"
    private static let configKey = "app_config_v1"

    public static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroupSuite) ?? .standard
    }

    public static func load() -> AppConfig {
        guard let data = defaults.data(forKey: configKey),
              let config = try? JSONDecoder().decode(AppConfig.self, from: data)
        else {
            return .default
        }
        return config
    }

    public static func save(_ config: AppConfig) {
        guard let data = try? JSONEncoder().encode(config) else { return }
        defaults.set(data, forKey: configKey)
    }

    /// App Group 是否可用（影响扩展能否读到主 App 的配置）
    public static var isAppGroupAvailable: Bool {
        UserDefaults(suiteName: appGroupSuite) != nil
    }
}
