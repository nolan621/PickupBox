import Foundation
import UserNotifications

enum Notifier {
    static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    /// 入柜当下的即时通知
    static func post(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    /// 到期前提醒。identifier 用取件记录的 id，方便取消和覆盖。
    static func scheduleExpiryReminder(for item: PickupItem, leadTime: TimeInterval = 2 * 3600) {
        let center = UNUserNotificationCenter.current()
        let identifier = item.id.uuidString

        center.removePendingNotificationRequests(withIdentifiers: [identifier])

        guard !item.isPicked, let expireAt = item.expireAt else { return }
        let fireDate = expireAt.addingTimeInterval(-leadTime)
        guard fireDate > Date() else { return }

        let content = UNMutableNotificationContent()
        content.title = "\(item.code) 快到期了"
        content.body = "\(item.stationName) · 还有不到 \(Int(leadTime / 3600)) 小时"
        content.sound = .default

        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)

        center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
    }

    static func cancelExpiryReminder(for item: PickupItem) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [item.id.uuidString])
    }

    /// 每次进 App 时补一遍，保证提醒和当前数据一致
    static func rescheduleAll(_ items: [PickupItem]) {
        for item in items {
            scheduleExpiryReminder(for: item)
        }
    }
}
