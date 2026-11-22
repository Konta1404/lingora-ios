import Foundation

// MARK: - Day stats

/// What the learner did on one day — drives XP, quests and achievements.
struct DayStat: Codable, Hashable {
    var xp = 0
    var lessons = 0
    var perfect = 0
    var practice = 0
    var tutor = 0
    var quests = 0
}

// MARK: - Daily quests

struct Quest: Identifiable, Hashable {
    enum Kind: String, CaseIterable { case xp, lessons, minutes, perfect, practice, tutor }
    var kind: Kind
    var target: Int
    var reward: Int
    var id: String { "\(kind.rawValue)-\(target)" }

    var title: String {
        switch kind {
        case .xp: L("Earn %lld XP", target)
        case .lessons: L("Finish %lld lessons", target)
        case .minutes: L("Practise for %lld minutes", target)
        case .perfect: L("Finish a lesson without mistakes")
        case .practice: L("Do a practice session")
        case .tutor: L("Send %lld messages to the tutor", target)
        }
    }

    var icon: String {
        switch kind {
        case .xp: "bolt.fill"
        case .lessons: "book.fill"
        case .minutes: "clock.fill"
        case .perfect: "sparkles"
        case .practice: "arrow.uturn.backward"
        case .tutor: "bubble.left.fill"
        }
    }

    func progress(_ d: DayStat, minutes: Int) -> Int {
        switch kind {
        case .xp: d.xp
        case .lessons: d.lessons
        case .minutes: minutes
        case .perfect: d.perfect
        case .practice: d.practice
        case .tutor: d.tutor
        }
    }

    /// Three quests a day, the same for the whole day: one XP quest + two others picked from the day's date.
    static func forDay(_ day: String) -> [Quest] {
        let seed = day.unicodeScalars.reduce(7) { ($0 &* 31 &+ Int($1.value)) & 0x7fffffff }
        let xpTargets = [20, 30, 40]
        let pool: [Quest] = [
            Quest(kind: .lessons, target: 2, reward: 10), Quest(kind: .lessons, target: 3, reward: 15),
            Quest(kind: .minutes, target: 10, reward: 10), Quest(kind: .minutes, target: 15, reward: 15),
            Quest(kind: .perfect, target: 1, reward: 15), Quest(kind: .practice, target: 1, reward: 10),
            Quest(kind: .tutor, target: 5, reward: 10),
        ]
        let a = seed % pool.count
        var b = (seed / 7) % pool.count
        if pool[b].kind == pool[a].kind { b = (b + 1) % pool.count }
        if pool[b].kind == pool[a].kind { b = (b + 2) % pool.count }
        return [Quest(kind: .xp, target: xpTargets[seed % 3], reward: 10), pool[a], pool[b]]
    }
}

// MARK: - Achievements

struct Achievement: Identifiable, Hashable {
    enum Kind: String, CaseIterable { case streak, xp, lessons, perfect, words, friends, quests }
    var kind: Kind
    var tiers: [Int]

    var id: String { kind.rawValue }
    var icon: String {
        switch kind {
        case .streak: "flame.fill"
        case .xp: "bolt.fill"
        case .lessons: "book.closed.fill"
        case .perfect: "sparkles"
        case .words: "character.book.closed.fill"
        case .friends: "person.2.fill"
        case .quests: "flag.checkered"
        }
    }
    var title: String {
        switch kind {
        case .streak: L("On fire")
        case .xp: L("Hard worker")
        case .lessons: L("Scholar")
        case .perfect: L("Flawless")
        case .words: L("Word collector")
        case .friends: L("Friendly")
        case .quests: L("Quest hunter")
        }
    }
    func detail(_ target: Int) -> String {
        switch kind {
        case .streak: L("Reach a %lld-day streak", target)
        case .xp: L("Earn %lld XP", target)
        case .lessons: L("Finish %lld lessons", target)
        case .perfect: L("Finish %lld lessons without mistakes", target)
        case .words: L("Master %lld words", target)
        case .friends: L("Add %lld friends", target)
        case .quests: L("Complete %lld daily quests", target)
        }
    }

    static let all: [Achievement] = [
        Achievement(kind: .streak, tiers: [3, 7, 30, 100, 365]),
        Achievement(kind: .xp, tiers: [100, 500, 2000, 5000, 10000]),
        Achievement(kind: .lessons, tiers: [5, 20, 50, 100, 250]),
        Achievement(kind: .perfect, tiers: [1, 10, 25, 50, 100]),
        Achievement(kind: .words, tiers: [25, 100, 250, 500, 1000]),
        Achievement(kind: .friends, tiers: [1, 3, 5, 10, 20]),
        Achievement(kind: .quests, tiers: [5, 20, 50, 100, 300]),
    ]

    /// Tiers reached (0…tiers.count) and the next target.
    func level(for value: Int) -> (reached: Int, next: Int?) {
        let reached = tiers.filter { value >= $0 }.count
        return (reached, tiers[safe: reached])
    }
}

/// A year of learning, for the year in review.
struct YearTotal: Codable, Hashable {
    var seconds = 0
    var xp = 0
    var lessons = 0
    var stories = 0
    var tutorMessages = 0
    var daysActive: Set<String> = []
    var xpByLanguage: [String: Int] = [:]
}
