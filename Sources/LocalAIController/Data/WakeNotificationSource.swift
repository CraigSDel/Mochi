import AppKit

@MainActor
protocol WakeNotificationSource: AnyObject {
    var center: NotificationCenter { get }
    var name: Notification.Name { get }
}

@MainActor
final class LiveWakeNotificationSource: WakeNotificationSource {
    let center: NotificationCenter = NSWorkspace.shared.notificationCenter
    let name: Notification.Name = NSWorkspace.didWakeNotification
}

@MainActor
final class NotificationCenterWakeSource: WakeNotificationSource {
    let center: NotificationCenter
    let name: Notification.Name

    init(center: NotificationCenter, name: Notification.Name = NSWorkspace.didWakeNotification) {
        self.center = center
        self.name = name
    }
}
