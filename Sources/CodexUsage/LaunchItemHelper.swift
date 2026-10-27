import Foundation
import ServiceManagement

enum LaunchItemHelper {
    static func isEnabled() -> Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// 设置开机登录项，返回设置后的实际状态
    @discardableResult
    static func setEnabled(_ on: Bool) -> Bool {
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            return isEnabled()
        }
        return isEnabled()
    }
}
