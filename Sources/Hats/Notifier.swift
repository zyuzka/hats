import Foundation
import UserNotifications

final class NotifierListener: NSObject, UNUserNotificationCenterDelegate {
    var openSettings: (() -> Void)?

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler(Notifier.getPresentation(notification.request.content.userInfo))
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let isClickOnOurs = Notifier.isClickOpeningSettings(
            response.actionIdentifier,
            response.notification.request.content.userInfo
        )
        if isClickOnOurs {
            DispatchQueue.main.async { [weak self] in self?.openSettings?() }
        }
        completionHandler()
    }
}

enum Notifier {
    static let opensSettingsKey = "dev.tmk.hats.opensSettings"
    private static let listener = NotifierListener()

    private static var centre: UNUserNotificationCenter? {
        guard Bundle.main.bundleIdentifier != nil else { return nil }
        return UNUserNotificationCenter.current()
    }

    static func askOnce() {
        guard let centre else { return }
        centre.requestAuthorization(options: [.alert]) { granted, error in
            Journal.log("notify.authorization", [
                "granted": String(granted),
                "error": error?.localizedDescription ?? "-",
            ])
        }
    }

    static func listen(openingSettings: @escaping () -> Void) {
        guard let centre else { return }
        listener.openSettings = openingSettings
        centre.delegate = listener
    }

    static func isOpeningSettings(_ userInfo: [AnyHashable: Any]) -> Bool {
        userInfo[opensSettingsKey] as? Bool == true
    }

    static func isClickOpeningSettings(_ action: String, _ userInfo: [AnyHashable: Any]) -> Bool {
        action == UNNotificationDefaultActionIdentifier && isOpeningSettings(userInfo)
    }

    static func getPresentation(_ userInfo: [AnyHashable: Any]) -> UNNotificationPresentationOptions {
        isOpeningSettings(userInfo)
            ? [
                .banner,
                .list,
            ]
            : []
    }

    static func post(title: String, body: String) {
        deliver(createContent(title: title, body: body))
    }

    static func postOpeningSettings(title: String, body: String) {
        deliver(createContentOpeningSettings(title: title, body: body))
    }

    static func createContent(title: String, body: String) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body

        return content
    }

    static func createContentOpeningSettings(title: String, body: String) -> UNMutableNotificationContent {
        let content = createContent(title: title, body: body)
        content.userInfo = [opensSettingsKey: true]

        return content
    }

    private static func deliver(_ content: UNMutableNotificationContent) {
        guard let centre else {
            Journal.log("notify.skipped", ["reason": "no bundle", "title": content.title])
            return
        }
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        centre.add(request) { error in
            guard let error else { return }
            Journal.log("notify.failed", ["reason": error.localizedDescription])
        }
    }
}
