import AppKit
import ServiceManagement

enum LoginItem {
    enum Action {
        case register
        case unregister
        case openApproval
    }

    struct MenuFace: Equatable {
        let title: String
        let state: NSControl.StateValue
        let isEnabled: Bool
        let action: Action
    }

    static var currentFace: MenuFace { face(for: SMAppService.mainApp.status) }

    static func face(for status: SMAppService.Status) -> MenuFace {
        switch status {
        case .enabled:
            return MenuFace(title: "Start at login", state: .on, isEnabled: true, action: .unregister)
        case .requiresApproval:
            return MenuFace(
                title: "Start at login — approve it in System Settings",
                state: .mixed,
                isEnabled: true,
                action: .openApproval
            )
        case .notRegistered, .notFound:
            return MenuFace(title: "Start at login", state: .off, isEnabled: true, action: .register)
        @unknown default:
            return MenuFace(title: "Start at login", state: .off, isEnabled: true, action: .register)
        }
    }

    static func perform(_ action: Action) throws -> String {
        switch action {
        case .unregister:
            try SMAppService.mainApp.unregister()
            return "loginItem.unregistered"
        case .openApproval:
            SMAppService.openSystemSettingsLoginItems()
            return "loginItem.approvalOpened"
        case .register:
            try SMAppService.mainApp.register()
            return "loginItem.registered"
        }
    }
}
