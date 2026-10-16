import UIKit

enum WeChatHelper {
    /// 尝试拉起微信（scheme 是否可用取决于微信版本，失败时静默）。
    static func openWeChat() {
        for scheme in ["weixin://", "wechat://"] {
            guard let url = URL(string: scheme) else { continue }
            if UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url)
                return
            }
        }
    }
}
