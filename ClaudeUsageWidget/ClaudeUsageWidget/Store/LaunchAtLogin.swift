import Foundation
import ServiceManagement

enum LaunchAtLogin {
    static func set(_ enabled: Bool) {
        let svc = SMAppService.mainApp
        do {
            if enabled {
                if svc.status != .enabled {
                    try svc.register()
                }
            } else {
                if svc.status == .enabled {
                    try svc.unregister()
                }
            }
        } catch {
            NSLog("LaunchAtLogin: \(error.localizedDescription)")
        }
    }

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }
}
