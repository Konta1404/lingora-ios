import Foundation
import UIKit
import CryptoKit

/// Friends, feed, challenges, chat and devices, served by lingora-backend (social.ts).
enum Social {
    struct Person: Decodable, Identifiable, Hashable {
        var uid: String
        var name: String
        var handle: String
        var hue: Double
        var langs: [String]
        var streak: Int
        var weekMinutes: Int
        var practisedToday: Bool
        var relation: String?          // none | requested | incoming | friend (search results only)
        var sharesActivity: Bool? = true
        var photo: Int? = 0
        var unread: Int? = 0
        var lastMessage: String?
        var lastMessageAt: Double?
        var lastFromMe: Bool?
        var photoVersion: Int { photo ?? 0 }
        var id: String { uid }
        var firstName: String { name.split(separator: " ").first.map(String.init) ?? name }
        var initial: String { String(name.first ?? "?").uppercased() }
        var atHandle: String { handle.isEmpty ? "" : "@" + handle }
    }

    struct FeedItem: Decodable, Identifiable, Hashable {
        var id: String
        var uid: String
        var name: String
        var hue: Double
        var type: String
        var params: [String: String]
        var createdAt: Double
        var cheers: Int
        var cheeredByMe: Bool
        var planId: String?
        var photo: Int?
        var date: Date { Date(timeIntervalSince1970: createdAt / 1000) }
        var firstName: String { name.split(separator: " ").first.map(String.init) ?? name }
    }

    struct Nudge: Decodable, Identifiable, Hashable { var id: String; var from: String; var name: String }

    struct Challenge: Decodable, Identifiable, Hashable {
        struct Row: Decodable, Hashable { var uid: String; var name: String; var hue: Double; var value: Int }
        var id: String
        var type: String               // duel | sprint | plan
        var creator: String
        var creatorName: String
        var invitedMe: Bool
        var pending: [String]
        var startDay: String
        var endDay: String?
        var goal: Int
        var lang: String?
        var title: String?
        var planId: String?
        var rows: [Row]
    }

    struct Overview: Decodable {
        var me: Person
        var friends: [Person]
        var incoming: [Person]
        var outgoing: [Person]
        var feed: [FeedItem]
        var nudges: [Nudge]
        var challenges: [Challenge]
    }

    struct Message: Decodable, Identifiable, Hashable {
        struct Correction: Decodable, Hashable { var wrong: String; var right: String; var note: String }
        var id: String
        var mine: Bool
        var text: String
        var createdAt: Double
        var correction: Correction?
    }

    struct Device: Decodable, Identifiable, Hashable {
        var id: String
        var name: String
        var model: String
        var os: String
        var lastSeen: Double
    }

    private struct Users: Decodable { var users: [Person] }
    private struct Relation: Decodable { var relation: String }
    private struct Handle: Decodable { var handle: String }
    private struct Messages: Decodable { var messages: [Message] }
    private struct Sent: Decodable { var id: String; var correction: Message.Correction? }
    private struct Devices: Decodable { var devices: [Device] }
    private struct SharedPlan: Decodable { var lang: String; var plan: String }
    private struct PlanRef: Decodable { var planId: String }
    private struct IDRef: Decodable { var id: String }
    private struct Ok: Decodable {}

    private static var days: [String: Any] { ["day": DateUtil.dayKey(), "weekStart": DateUtil.dayKey(DateUtil.weekStart())] }

    // Profile
    static func sync(name: String, langs: [String]) async throws -> String {
        let r: Handle = try await Backend.call("profileSync", ["name": name, "langs": langs])
        return r.handle
    }
    static func setHandle(_ handle: String) async throws -> String {
        let r: Handle = try await Backend.call("setHandle", ["handle": handle])
        return r.handle
    }
    static func report(days: [String: Int], event: (type: String, params: [String: String])?) async throws {
        var payload: [String: Any] = ["day": DateUtil.dayKey(), "days": days]
        if let event { payload["event"] = ["type": event.type, "params": event.params] }
        let _: Ok = try await Backend.call("reportActivity", payload)
    }

    static func setPrivacy(shareActivity: Bool) async throws {
        let _: Ok = try await Backend.call("setPrivacy", ["shareActivity": shareActivity])
    }
    private struct Photo: Decodable { var photo: Int }
    /// Uploads a profile photo (nil removes it). Returns the new photo version.
    static func setAvatar(_ jpeg: Data?) async throws -> Int {
        let image: Any = jpeg.map { $0.base64EncodedString() } ?? NSNull()
        let r: Photo = try await Backend.call("setAvatar", ["image": image])
        return r.photo
    }

    // Friends
    static func overview() async throws -> Overview { try await Backend.call("friendsOverview", days) }
    static func search(_ q: String) async throws -> [Person] {
        var p = days; p["query"] = q
        let r: Users = try await Backend.call("searchUsers", p)
        return r.users
    }
    /// Matches contacts by a SHA-256 of their email address; addresses never leave the phone.
    static func matchContacts(emails: [String]) async throws -> [Person] {
        var p = days
        p["hashes"] = Array(Set(emails.map { sha256($0.trimmingCharacters(in: .whitespaces).lowercased()) }))
        let r: Users = try await Backend.call("matchContacts", p)
        return r.users
    }
    static func request(uid: String? = nil, handle: String? = nil) async throws -> String {
        var p: [String: Any] = [:]
        if let uid { p["uid"] = uid }
        if let handle { p["handle"] = handle }
        let r: Relation = try await Backend.call("sendFriendRequest", p)
        return r.relation
    }
    static func respond(uid: String, accept: Bool) async throws {
        let _: Relation = try await Backend.call("respondFriendRequest", ["uid": uid, "accept": accept])
    }
    static func remove(uid: String) async throws {
        let _: Relation = try await Backend.call("removeFriend", ["uid": uid])
    }
    static func cheer(owner: String, id: String) async throws {
        let _: Ok = try await Backend.call("cheer", ["owner": owner, "id": id])
    }
    static func nudge(uid: String) async throws {
        let _: Ok = try await Backend.call("nudge", ["uid": uid, "day": DateUtil.dayKey()])
    }
    static func markNudgesSeen(_ ids: [String]) async throws {
        let _: Ok = try await Backend.call("markNudgesSeen", ["ids": ids])
    }

    // Challenges & shared plans
    static func createChallenge(type: String, friends: [String], goalMinutes: Int? = nil, endDay: String? = nil,
                                lang: String? = nil, title: String? = nil, plan: WeeklyPlan? = nil) async throws {
        var p: [String: Any] = ["type": type, "friends": friends, "day": DateUtil.dayKey()]
        if let goalMinutes { p["goalMinutes"] = goalMinutes }
        if let endDay { p["endDay"] = endDay }
        if let lang { p["lang"] = lang }
        if let title { p["title"] = title }
        if let plan { p["plan"] = try encode(plan) }
        let _: IDRef = try await Backend.call("createChallenge", p)
    }
    static func respondChallenge(id: String, accept: Bool) async throws {
        let _: Ok = try await Backend.call("respondChallenge", ["id": id, "accept": accept])
    }
    static func leaveChallenge(id: String) async throws {
        let _: Ok = try await Backend.call("leaveChallenge", ["id": id])
    }
    static func sharePlan(_ plan: WeeklyPlan, lang: String, title: String) async throws {
        let _: PlanRef = try await Backend.call("sharePlan", ["lang": lang, "title": title, "plan": try encode(plan)])
    }
    static func sharedPlan(id: String) async throws -> (lang: String, plan: WeeklyPlan) {
        let r: SharedPlan = try await Backend.call("getSharedPlan", ["planId": id])
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (r.lang, try decoder.decode(WeeklyPlan.self, from: Data(r.plan.utf8)))
    }

    // Chat
    static func messages(with uid: String) async throws -> [Message] {
        let r: Messages = try await Backend.call("chatMessages", ["uid": uid])
        return r.messages
    }
    static func send(_ text: String, to uid: String, language: Language?) async throws -> Message.Correction? {
        var p: [String: Any] = ["uid": uid, "text": text, "uiLanguage": AppLocale.tag]
        if let language { p["language"] = ["name": language.name, "isCustom": language.isCustom] }
        let r: Sent = try await Backend.call("sendChatMessage", p)
        return r.correction
    }

    // Devices
    @MainActor static var deviceID: String { UIDevice.current.identifierForVendor?.uuidString ?? "unknown" }
    @MainActor static func registerThisDevice() async throws {
        var sys = utsname()
        uname(&sys)
        let machine = withUnsafeBytes(of: &sys.machine) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
        let d = UIDevice.current
        let _: IDRef = try await Backend.call("registerDevice", [
            "id": deviceID, "name": d.name, "model": machine,
            "os": "\(d.systemName) \(d.systemVersion)"
        ])
    }
    static func devices() async throws -> [Device] {
        let r: Devices = try await Backend.call("listDevices", [:])
        return r.devices
    }
    static func removeDevice(_ id: String) async throws {
        let _: Ok = try await Backend.call("removeDevice", ["id": id])
    }

    private static func encode(_ plan: WeeklyPlan) throws -> String {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return String(decoding: try e.encode(plan), as: UTF8.self)
    }

    static func sha256(_ s: String) -> String {
        SHA256.hash(data: Data(s.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
