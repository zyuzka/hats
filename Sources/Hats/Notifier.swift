import Foundation
import UserNotifications

enum Notifier {
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

    static func post(title: String, body: String) {
        guard let centre else {
            Journal.log("notify.skipped", ["reason": "no bundle", "title": title])
            return
        }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
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
