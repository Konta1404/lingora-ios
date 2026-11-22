import Foundation
import UIKit
import UserNotifications
import BackgroundTasks
import FirebaseAuth

/// New messages, friend requests, nudges and challenge invites.
/// Without a paid Apple developer account there is no push, so the app checks the backend itself:
/// every 30 s while open (in-app banner) and through iOS background refresh (local notification).
enum MessageAlerts {
    static let refreshTaskID = "com.veselin.lingora.refresh"
    private static let storeKey = "lingora.alerts.seen"
    static let enabledKey = "lingora.alerts.enabled"

    struct Event { var id: String; var title: String; var body: String; var friend: String? }

    private struct Seen: Codable {
        var messages: [String: Double] = [:]
        var ids: Set<String> = []
    }

    /// Returns what's new since last time and remembers it. The first run only records a baseline.
    static func newEvents(in o: Social.Overview, openChat: String?) -> [Event] {
        let defaults = UserDefaults.standard
        let first = defaults.data(forKey: storeKey) == nil
        var seen = defaults.data(forKey: storeKey).flatMap { try? JSONDecoder().decode(Seen.self, from: $0) } ?? Seen()
        var out: [Event] = []

        for f in o.friends {
            guard let at = f.lastMessageAt, f.lastFromMe != true else { continue }
            if at > (seen.messages[f.uid] ?? 0) {
                seen.messages[f.uid] = at
                if (f.unread ?? 0) > 0 && f.uid != openChat {
                    out.append(Event(id: "msg-\(f.uid)-\(Int(at))", title: f.name, body: f.lastMessage ?? "", friend: f.uid))
                }
            }
        }
        for p in o.incoming where !seen.ids.contains("req-\(p.uid)") {
            seen.ids.insert("req-\(p.uid)")
            out.append(Event(id: "req-\(p.uid)", title: L("Friend request"), body: L("%@ wants to be friends", p.name), friend: nil))
        }
        for n in o.nudges where !seen.ids.contains("nudge-\(n.id)") {
            seen.ids.insert("nudge-\(n.id)")
            out.append(Event(id: "nudge-\(n.id)", title: n.name, body: L("%@ nudged you — a few minutes today?", n.name), friend: n.from))
        }
        for c in o.challenges where c.invitedMe && !seen.ids.contains("ch-\(c.id)") {
            seen.ids.insert("ch-\(c.id)")
            out.append(Event(id: "ch-\(c.id)", title: c.creatorName, body: L("%@ invited you to a challenge", c.creatorName), friend: nil))
        }
        if seen.ids.count > 400 { seen.ids = Set(seen.ids.suffix(200)) }
        if let data = try? JSONEncoder().encode(seen) { defaults.set(data, forKey: storeKey) }
        return first ? [] : out
    }

    static func unreadCount(_ o: Social.Overview) -> Int {
        o.friends.reduce(0) { $0 + ($1.unread ?? 0) } + o.incoming.count
    }

    static func reset() { UserDefaults.standard.removeObject(forKey: storeKey) }

    // MARK: Local notifications

    static func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    static func post(_ events: [Event]) {
        let center = UNUserNotificationCenter.current()
        for e in events.prefix(5) {
            let c = UNMutableNotificationContent()
            c.title = e.title
            c.body = e.body
            c.sound = .default
            c.threadIdentifier = e.friend ?? "lingora"
            if let f = e.friend { c.userInfo = ["friend": f] }
            center.add(UNNotificationRequest(identifier: e.id, content: c, trigger: nil))
        }
    }

    static func setBadge(_ n: Int) {
        UNUserNotificationCenter.current().setBadgeCount(n) { _ in }
    }

    // MARK: Background refresh

    static func registerBackgroundRefresh() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: refreshTaskID, using: nil) { task in
            scheduleBackgroundRefresh()
            let work = Task {
                await checkInBackground()
                task.setTaskCompleted(success: true)
            }
            task.expirationHandler = { work.cancel() }
        }
    }

    static func scheduleBackgroundRefresh() {
        let req = BGAppRefreshTaskRequest(identifier: refreshTaskID)
        req.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(req)
    }

    static func checkInBackground() async {
        let enabled = UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
        guard enabled, Backend.isConfigured, Auth.auth().currentUser != nil,
              let o = try? await Social.overview() else { return }
        post(newEvents(in: o, openChat: nil))
        setBadge(unreadCount(o))
    }
}

/// Opens the right chat when a notification is tapped; shows reminders while the app is open.
final class NotificationRouter: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationRouter()
    @Published var openFriend: String?

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler done: @escaping () -> Void) {
        let friend = response.notification.request.content.userInfo["friend"] as? String
        DispatchQueue.main.async { self.openFriend = friend ?? "" }
        done()
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler done: @escaping (UNNotificationPresentationOptions) -> Void) {
        // Friend events are shown in-app while Lingora is open; daily reminders still show as banners.
        done(notification.request.identifier == "daily" ? [.banner, .sound] : [])
    }
}
