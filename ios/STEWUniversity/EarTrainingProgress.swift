import Foundation
import Combine
import UserNotifications

enum EarTrainingMode: String, CaseIterable, Codable, Identifiable {
    case interval = "Intervals"
    case chord = "Chords"
    case note = "Notes"

    var id: String { rawValue }
}

struct EarTrainingQuestion: Equatable {
    let label: String
    let skillID: String
    let mode: EarTrainingMode
    let tier: Int
    let midis: [Int]
    let choices: [String]
}

struct SkillMastery: Codable, Equatable {
    var attempts = 0
    var correct = 0
    var score = 0.0

    var title: String {
        switch score {
        case 85...: "Mastered"
        case 70...: "Strong"
        case 45...: "Familiar"
        case 20...: "Learning"
        default: "Beginner"
        }
    }

    mutating func record(correct wasCorrect: Bool) {
        attempts += 1
        if wasCorrect {
            correct += 1
            score += (100 - score) * 0.15
        } else {
            score *= 0.80
        }
        score = min(100, max(0, score))
    }
}

enum ListenerLevel: String, CaseIterable, Codable, Identifiable {
    case curious = "Curious Listener"
    case developing = "Developing Listener"
    case focused = "Focused Listener"
    case tuned = "Tuned Listener"
    case skilled = "Skilled Listener"
    case golden = "Golden Ear"

    var id: String { rawValue }
    var minimumXP: Int {
        switch self {
        case .curious: 0
        case .developing: 250
        case .focused: 600
        case .tuned: 1_200
        case .skilled: 2_200
        case .golden: 3_600
        }
    }

    static func level(for xp: Int) -> ListenerLevel {
        allCases.last(where: { xp >= $0.minimumXP }) ?? .curious
    }

    var number: Int { Self.allCases.firstIndex(of: self)! + 1 }
    var next: ListenerLevel? { Self.allCases.dropFirst(number).first }
}

enum DailyChallengeKind: String, Codable, CaseIterable {
    case comboThree, intervalThree, chordThree, noteThree, perfectFive
}

struct DailyChallenge: Codable, Equatable {
    let dayKey: String
    let kind: DailyChallengeKind
    var progress: Int
    var completed: Bool

    var target: Int { kind == .perfectFive ? 5 : 3 }
    var title: String {
        switch kind {
        case .comboThree: "Build a 3-answer combo"
        case .intervalThree: "Identify 3 intervals"
        case .chordThree: "Identify 3 chords"
        case .noteThree: "Identify 3 notes"
        case .perfectFive: "Get 5 answers right in a row"
        }
    }
    var symbol: String {
        switch kind {
        case .comboThree: "bolt.fill"
        case .intervalThree: "arrow.up.right"
        case .chordThree: "music.note"
        case .noteThree: "pianokeys"
        case .perfectFive: "star.fill"
        }
    }
}

enum AchievementID: String, CaseIterable, Codable, Identifiable {
    case firstCorrect, firstGoal, comboFive, perfectFive, weekStreak
    case intervalMastery, chordMastery, noteMastery, goldenEar

    var id: String { rawValue }
    var title: String {
        switch self {
        case .firstCorrect: "First Note"
        case .firstGoal: "Daily Listener"
        case .comboFive: "On a Roll"
        case .perfectFive: "Five in a Row"
        case .weekStreak: "Week of Ears"
        case .intervalMastery: "Interval Explorer"
        case .chordMastery: "Chord Detective"
        case .noteMastery: "Note Navigator"
        case .goldenEar: "Golden Ear"
        }
    }
    var detail: String {
        switch self {
        case .firstCorrect: "Answer your first question correctly."
        case .firstGoal: "Complete your first daily goal."
        case .comboFive: "Build a five-answer combo."
        case .perfectFive: "Get five answers right in a row."
        case .weekStreak: "Complete your goal seven days in a row."
        case .intervalMastery: "Master every interval."
        case .chordMastery: "Master every chord quality."
        case .noteMastery: "Master every note name."
        case .goldenEar: "Reach the Golden Ear listener level."
        }
    }
    var symbol: String {
        switch self {
        case .firstCorrect: "music.note"
        case .firstGoal: "checkmark.seal.fill"
        case .comboFive: "bolt.fill"
        case .perfectFive: "star.fill"
        case .weekStreak: "flame.fill"
        case .intervalMastery: "arrow.up.right.circle.fill"
        case .chordMastery: "music.note.list"
        case .noteMastery: "pianokeys"
        case .goldenEar: "trophy.fill"
        }
    }
}

struct DailyPracticeRecord: Codable, Equatable {
    let dayKey: String
    var answered = 0
    var correct = 0
    var xpEarned = 0
    var currentCombo = 0
    var bestCombo = 0
    var perfectRun = 0
    var goalRewardAwarded = false
    var challenge: DailyChallenge
}

struct EarTrainingProfile: Codable, Equatable {
    var version = 2
    var totalXP = 0
    var currentStreak = 0
    var longestStreak = 0
    var lastGoalCompletionDay: String?
    var dailyGoal = 5
    var mastery: [String: SkillMastery] = [:]
    var unlockedAchievements: Set<AchievementID> = []
    var remindersEnabled = false
    var reminderHour = 19
    var reminderMinute = 0
    var today: DailyPracticeRecord?
    var completedGoalDays: [String] = []

    enum CodingKeys: String, CodingKey {
        case version, totalXP, currentStreak, longestStreak, lastGoalCompletionDay
        case dailyGoal, mastery, unlockedAchievements, remindersEnabled
        case reminderHour, reminderMinute, today, completedGoalDays
    }

    init() {}

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        version = try values.decodeIfPresent(Int.self, forKey: .version) ?? 1
        totalXP = try values.decodeIfPresent(Int.self, forKey: .totalXP) ?? 0
        currentStreak = try values.decodeIfPresent(Int.self, forKey: .currentStreak) ?? 0
        longestStreak = try values.decodeIfPresent(Int.self, forKey: .longestStreak) ?? 0
        lastGoalCompletionDay = try values.decodeIfPresent(String.self, forKey: .lastGoalCompletionDay)
        dailyGoal = try values.decodeIfPresent(Int.self, forKey: .dailyGoal) ?? 5
        mastery = try values.decodeIfPresent([String: SkillMastery].self, forKey: .mastery) ?? [:]
        unlockedAchievements = try values.decodeIfPresent(Set<AchievementID>.self, forKey: .unlockedAchievements) ?? []
        remindersEnabled = try values.decodeIfPresent(Bool.self, forKey: .remindersEnabled) ?? false
        reminderHour = try values.decodeIfPresent(Int.self, forKey: .reminderHour) ?? 19
        reminderMinute = try values.decodeIfPresent(Int.self, forKey: .reminderMinute) ?? 0
        today = try values.decodeIfPresent(DailyPracticeRecord.self, forKey: .today)
        completedGoalDays = try values.decodeIfPresent([String].self, forKey: .completedGoalDays) ?? []
        if completedGoalDays.isEmpty, let lastGoalCompletionDay { completedGoalDays = [lastGoalCompletionDay] }
        version = 2
    }
}

struct MasteryCategoryChange: Equatable {
    let skillID: String
    let skillLabel: String
    let previousTitle: String
    let currentTitle: String
    let previousScore: Double
    let currentScore: Double
}

struct AnswerOutcome: Equatable {
    let correct: Bool
    let xpEarned: Int
    let combo: Int
    let goalCompleted: Bool
    let challengeCompleted: Bool
    let newlyUnlocked: [AchievementID]
    let previousTotalXP: Int
    let currentTotalXP: Int
    let previousLevel: ListenerLevel
    let currentLevel: ListenerLevel
    let masteryChange: MasteryCategoryChange?
    let challengeProgress: Int
    let challengeTarget: Int
}

enum EarTrainingUXEvent: Identifiable, Equatable {
    case achievement(AchievementID)
    case levelUp(ListenerLevel)
    case mastery(MasteryCategoryChange)
    case results

    var id: String {
        switch self {
        case let .achievement(value): "achievement.\(value.rawValue)"
        case let .levelUp(value): "level.\(value.rawValue)"
        case let .mastery(value): "mastery.\(value.skillID).\(value.currentTitle)"
        case .results: "results"
        }
    }

    static func events(for outcome: AnswerOutcome) -> [EarTrainingUXEvent] {
        var events = outcome.newlyUnlocked.map(EarTrainingUXEvent.achievement)
        if outcome.previousLevel != outcome.currentLevel { events.append(.levelUp(outcome.currentLevel)) }
        if let change = outcome.masteryChange,
           change.previousTitle != change.currentTitle,
           change.currentScore > change.previousScore {
            events.append(.mastery(change))
        }
        if outcome.goalCompleted { events.append(.results) }
        return events
    }
}

struct EarTrainingEventQueue: Equatable {
    private(set) var pending: [EarTrainingUXEvent] = []
    mutating func enqueue(_ events: [EarTrainingUXEvent]) { pending.append(contentsOf: events) }
    mutating func next() -> EarTrainingUXEvent? { pending.isEmpty ? nil : pending.removeFirst() }
    mutating func clear() { pending.removeAll() }
}

protocol EarTrainingProfilePersisting {
    func load() -> EarTrainingProfile?
    func save(_ profile: EarTrainingProfile)
}

struct UserDefaultsEarTrainingPersistence: EarTrainingProfilePersisting {
    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, key: String = "stew.earTraining.profile.v1") {
        self.defaults = defaults
        self.key = key
    }

    func load() -> EarTrainingProfile? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(EarTrainingProfile.self, from: data)
    }

    func save(_ profile: EarTrainingProfile) {
        guard let data = try? JSONEncoder().encode(profile) else { return }
        defaults.set(data, forKey: key)
    }
}

@MainActor
protocol EarTrainingReminderScheduling: AnyObject {
    func requestAuthorization() async -> Bool
    func scheduleNext(hour: Int, minute: Int, now: Date, calendar: Calendar) async
    func cancel()
}

@MainActor
final class LocalEarTrainingReminderScheduler: EarTrainingReminderScheduling {
    private let center = UNUserNotificationCenter.current()
    private let identifier = "stew.ear-training.daily"

    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    func scheduleNext(hour: Int, minute: Int, now: Date, calendar: Calendar) async {
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = hour
        components.minute = minute
        var fireDate = calendar.date(from: components) ?? now
        if fireDate <= now { fireDate = calendar.date(byAdding: .day, value: 1, to: fireDate) ?? now.addingTimeInterval(86_400) }
        let content = UNMutableNotificationContent()
        content.title = "Keep your ear sharp"
        content.body = "Your STEW daily ear workout is ready."
        content.sound = .default
        let trigger = UNCalendarNotificationTrigger(dateMatching: calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate), repeats: false)
        try? await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
    }

    func cancel() { center.removePendingNotificationRequests(withIdentifiers: [identifier]) }
}

@MainActor
final class EarTrainingProgressStore: ObservableObject {
    @Published private(set) var profile: EarTrainingProfile
    @Published var notificationPermissionDenied = false

    private let persistence: EarTrainingProfilePersisting
    private let reminderScheduler: EarTrainingReminderScheduling
    private var calendar: Calendar
    private let now: () -> Date

    init(
        persistence: EarTrainingProfilePersisting = UserDefaultsEarTrainingPersistence(),
        reminderScheduler: EarTrainingReminderScheduling = LocalEarTrainingReminderScheduler(),
        calendar: Calendar = .autoupdatingCurrent,
        now: @escaping () -> Date = Date.init
    ) {
        self.persistence = persistence
        self.reminderScheduler = reminderScheduler
        self.calendar = calendar
        self.now = now
        profile = persistence.load() ?? EarTrainingProfile()
        reconcile(for: now())
    }

    var today: DailyPracticeRecord { profile.today! }
    var level: ListenerLevel { .level(for: profile.totalXP) }
    var nextLevelProgress: Double {
        guard let next = level.next else { return 1 }
        return Double(profile.totalXP - level.minimumXP) / Double(next.minimumXP - level.minimumXP)
    }
    var questionsRemaining: Int { max(0, profile.dailyGoal - today.answered) }
    var goalProgress: Double { min(1, Double(today.answered) / Double(profile.dailyGoal)) }

    func reconcile(for date: Date? = nil) {
        let date = date ?? now()
        let key = dayKey(for: date)
        if profile.today?.dayKey != key {
            profile.today = DailyPracticeRecord(dayKey: key, challenge: Self.challenge(for: key))
        }
        if let last = profile.lastGoalCompletionDay, last != key, !isYesterday(last, relativeTo: date) {
            profile.currentStreak = 0
        }
        save()
    }

    func setDailyGoal(_ goal: Int) {
        guard [5, 10, 15].contains(goal) else { return }
        profile.dailyGoal = goal
        let completed = awardGoalIfNeeded(on: now())
        if completed, profile.remindersEnabled { reminderScheduler.cancel() }
        save()
    }

    func setReminder(enabled: Bool) async {
        if enabled {
            let allowed = await reminderScheduler.requestAuthorization()
            notificationPermissionDenied = !allowed
            profile.remindersEnabled = allowed
            if allowed { await scheduleReminder() }
        } else {
            profile.remindersEnabled = false
            reminderScheduler.cancel()
        }
        save()
    }

    func setReminderTime(_ date: Date) async {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        profile.reminderHour = parts.hour ?? 19
        profile.reminderMinute = parts.minute ?? 0
        save()
        if profile.remindersEnabled { await scheduleReminder() }
    }

    func handleForeground() async {
        reconcile()
        if profile.remindersEnabled { await scheduleReminder() }
    }

    @discardableResult
    func answer(_ question: EarTrainingQuestion, choice: String, date: Date? = nil) -> AnswerOutcome {
        let date = date ?? now()
        reconcile(for: date)
        let wasCorrect = choice == question.label
        let previousAchievements = profile.unlockedAchievements
        let previousTotalXP = profile.totalXP
        let previousLevel = ListenerLevel.level(for: previousTotalXP)
        let previousMastery = profile.mastery[question.skillID] ?? SkillMastery()
        var record = profile.today!
        record.answered += 1
        if wasCorrect {
            record.correct += 1
            record.currentCombo += 1
            record.perfectRun += 1
            record.bestCombo = max(record.bestCombo, record.currentCombo)
        } else {
            record.currentCombo = 0
            record.perfectRun = 0
        }
        let answerXP = wasCorrect ? 10 + min(10, max(0, record.currentCombo - 1) * 2) : 0
        record.xpEarned += answerXP
        profile.totalXP += answerXP
        var mastery = profile.mastery[question.skillID] ?? SkillMastery()
        mastery.record(correct: wasCorrect)
        profile.mastery[question.skillID] = mastery
        updateChallenge(&record, question: question, correct: wasCorrect)
        profile.today = record
        let goalCompleted = awardGoalIfNeeded(on: date)
        let challengeCompleted = awardChallengeIfNeeded()
        evaluateAchievements()
        save()
        let unlockedSet = profile.unlockedAchievements.subtracting(previousAchievements)
        let newAchievements = AchievementID.allCases.filter(unlockedSet.contains)
        if goalCompleted, profile.remindersEnabled { reminderScheduler.cancel() }
        let currentMastery = profile.mastery[question.skillID] ?? SkillMastery()
        let masteryChange = MasteryCategoryChange(
            skillID: question.skillID,
            skillLabel: question.label,
            previousTitle: previousMastery.title,
            currentTitle: currentMastery.title,
            previousScore: previousMastery.score,
            currentScore: currentMastery.score
        )
        return AnswerOutcome(
            correct: wasCorrect,
            xpEarned: answerXP,
            combo: profile.today!.currentCombo,
            goalCompleted: goalCompleted,
            challengeCompleted: challengeCompleted,
            newlyUnlocked: newAchievements,
            previousTotalXP: previousTotalXP,
            currentTotalXP: profile.totalXP,
            previousLevel: previousLevel,
            currentLevel: ListenerLevel.level(for: profile.totalXP),
            masteryChange: masteryChange,
            challengeProgress: profile.today!.challenge.progress,
            challengeTarget: profile.today!.challenge.target
        )
    }

    func mastery(for skillID: String) -> SkillMastery { profile.mastery[skillID] ?? SkillMastery() }
    func averageMastery(for mode: EarTrainingMode) -> Double {
        let skills = EarTrainingQuestionFactory.skills(for: mode)
        guard !skills.isEmpty else { return 0 }
        return skills.map { mastery(for: $0.id).score }.reduce(0, +) / Double(skills.count)
    }

    func achievementProgress(_ achievement: AchievementID) -> Double {
        if profile.unlockedAchievements.contains(achievement) { return 1 }
        switch achievement {
        case .firstCorrect: return min(1, Double(profile.today?.correct ?? 0))
        case .firstGoal: return 0
        case .comboFive, .perfectFive: return min(1, Double(today.bestCombo) / 5)
        case .weekStreak: return min(1, Double(profile.currentStreak) / 7)
        case .intervalMastery: return averageMastery(for: .interval) / 85
        case .chordMastery: return averageMastery(for: .chord) / 85
        case .noteMastery: return averageMastery(for: .note) / 85
        case .goldenEar: return min(1, Double(profile.totalXP) / 3_600)
        }
    }

    private func awardGoalIfNeeded(on date: Date) -> Bool {
        guard var record = profile.today, record.answered >= profile.dailyGoal, !record.goalRewardAwarded else { return false }
        record.goalRewardAwarded = true
        record.xpEarned += 25
        profile.totalXP += 25
        let key = dayKey(for: date)
        if let last = profile.lastGoalCompletionDay, isYesterday(last, relativeTo: date) {
            profile.currentStreak += 1
        } else if profile.lastGoalCompletionDay != key {
            profile.currentStreak = 1
        }
        profile.lastGoalCompletionDay = key
        if !profile.completedGoalDays.contains(key) {
            profile.completedGoalDays.append(key)
            profile.completedGoalDays = Array(profile.completedGoalDays.sorted().suffix(90))
        }
        profile.longestStreak = max(profile.longestStreak, profile.currentStreak)
        profile.today = record
        return true
    }

    private func updateChallenge(_ record: inout DailyPracticeRecord, question: EarTrainingQuestion, correct: Bool) {
        guard !record.challenge.completed else { return }
        switch record.challenge.kind {
        case .comboThree:
            record.challenge.progress = min(record.challenge.target, record.currentCombo)
        case .intervalThree where correct && question.mode == .interval,
             .chordThree where correct && question.mode == .chord,
             .noteThree where correct && question.mode == .note:
            record.challenge.progress += 1
        case .perfectFive:
            record.challenge.progress = min(record.challenge.target, record.perfectRun)
        default: break
        }
    }

    private func awardChallengeIfNeeded() -> Bool {
        guard var record = profile.today, !record.challenge.completed, record.challenge.progress >= record.challenge.target else { return false }
        record.challenge.completed = true
        record.xpEarned += 30
        profile.totalXP += 30
        profile.today = record
        return true
    }

    private func evaluateAchievements() {
        let totalCorrect = profile.mastery.values.reduce(0) { $0 + $1.correct }
        if totalCorrect > 0 { profile.unlockedAchievements.insert(.firstCorrect) }
        if profile.lastGoalCompletionDay != nil { profile.unlockedAchievements.insert(.firstGoal) }
        if today.bestCombo >= 5 { profile.unlockedAchievements.insert(.comboFive); profile.unlockedAchievements.insert(.perfectFive) }
        if profile.currentStreak >= 7 { profile.unlockedAchievements.insert(.weekStreak) }
        if modeMastered(.interval) { profile.unlockedAchievements.insert(.intervalMastery) }
        if modeMastered(.chord) { profile.unlockedAchievements.insert(.chordMastery) }
        if modeMastered(.note) { profile.unlockedAchievements.insert(.noteMastery) }
        if level == .golden { profile.unlockedAchievements.insert(.goldenEar) }
    }

    private func modeMastered(_ mode: EarTrainingMode) -> Bool {
        EarTrainingQuestionFactory.skills(for: mode).allSatisfy { mastery(for: $0.id).score >= 85 }
    }

    private func scheduleReminder() async {
        var schedulingDate = now()
        if profile.today?.goalRewardAwarded == true,
           let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: schedulingDate)) {
            schedulingDate = tomorrow
        }
        await reminderScheduler.scheduleNext(hour: profile.reminderHour, minute: profile.reminderMinute, now: schedulingDate, calendar: calendar)
    }

    private func save() { persistence.save(profile) }
    private func dayKey(for date: Date) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
    private func isYesterday(_ key: String, relativeTo date: Date) -> Bool {
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: date) else { return false }
        return dayKey(for: yesterday) == key
    }

    func weekDayKeys(containing date: Date? = nil) -> [String] {
        let date = date ?? now()
        let start = calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
        return (0..<7).compactMap { offset in calendar.date(byAdding: .day, value: offset, to: start).map(dayKey) }
    }

    static func challenge(for dayKey: String) -> DailyChallenge {
        let value = dayKey.utf8.reduce(0) { ($0 + Int($1)) % DailyChallengeKind.allCases.count }
        return DailyChallenge(dayKey: dayKey, kind: DailyChallengeKind.allCases[value], progress: 0, completed: false)
    }
}

struct EarTrainingSkill: Equatable {
    let id: String
    let label: String
    let mode: EarTrainingMode
    let tier: Int
    let semitones: [Int]
}

enum EarTrainingQuestionFactory {
    private static let intervalSkills = [
        EarTrainingSkill(id: "interval.minor3", label: "Minor 3rd", mode: .interval, tier: 1, semitones: [0, 3]),
        EarTrainingSkill(id: "interval.major3", label: "Major 3rd", mode: .interval, tier: 1, semitones: [0, 4]),
        EarTrainingSkill(id: "interval.perfect5", label: "Perfect 5th", mode: .interval, tier: 1, semitones: [0, 7]),
        EarTrainingSkill(id: "interval.octave", label: "Octave", mode: .interval, tier: 1, semitones: [0, 12]),
        EarTrainingSkill(id: "interval.major2", label: "Major 2nd", mode: .interval, tier: 2, semitones: [0, 2]),
        EarTrainingSkill(id: "interval.perfect4", label: "Perfect 4th", mode: .interval, tier: 2, semitones: [0, 5]),
        EarTrainingSkill(id: "interval.minor2", label: "Minor 2nd", mode: .interval, tier: 3, semitones: [0, 1])
    ]
    private static let chordSkills = [
        EarTrainingSkill(id: "chord.major", label: "Major", mode: .chord, tier: 1, semitones: [0, 4, 7]),
        EarTrainingSkill(id: "chord.minor", label: "Minor", mode: .chord, tier: 1, semitones: [0, 3, 7]),
        EarTrainingSkill(id: "chord.diminished", label: "Diminished", mode: .chord, tier: 2, semitones: [0, 3, 6]),
        EarTrainingSkill(id: "chord.augmented", label: "Augmented", mode: .chord, tier: 2, semitones: [0, 4, 8])
    ]
    private static let noteSkills: [EarTrainingSkill] = {
        let names = ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"]
        let naturals: Set<Int> = [0, 2, 4, 5, 7, 9, 11]
        return names.enumerated().map { index, name in
            EarTrainingSkill(id: "note.\(index)", label: name, mode: .note, tier: naturals.contains(index) ? 1 : 2, semitones: [index])
        }
    }()

    static func skills(for mode: EarTrainingMode) -> [EarTrainingSkill] {
        switch mode { case .interval: intervalSkills; case .chord: chordSkills; case .note: noteSkills }
    }

    static func unlockedTier(for mode: EarTrainingMode, profile: EarTrainingProfile) -> Int {
        let all = skills(for: mode)
        var unlocked = 1
        let maximum = all.map(\.tier).max() ?? 1
        while unlocked < maximum {
            let tierSkills = all.filter { $0.tier == unlocked }
            let records = tierSkills.map { profile.mastery[$0.id] ?? SkillMastery() }
            let attempts = records.reduce(0) { $0 + $1.attempts }
            let average = records.isEmpty ? 0 : records.map(\.score).reduce(0, +) / Double(records.count)
            guard attempts >= 12, average >= 70 else { break }
            unlocked += 1
        }
        return unlocked
    }

    static func makeQuestion(for mode: EarTrainingMode, profile: EarTrainingProfile, random: (Range<Int>) -> Int = { Int.random(in: $0) }) -> EarTrainingQuestion {
        let all = skills(for: mode)
        let tier = unlockedTier(for: mode, profile: profile)
        let unlocked = all.filter { $0.tier <= tier }
        let roll = random(0..<100)
        let skill: EarTrainingSkill
        if roll < 60 {
            skill = unlocked.min { (profile.mastery[$0.id]?.score ?? 0) < (profile.mastery[$1.id]?.score ?? 0) } ?? unlocked[0]
        } else if roll < 85 {
            skill = unlocked[random(0..<unlocked.count)]
        } else {
            let nextTier = all.filter { $0.tier == tier + 1 }
            skill = nextTier.isEmpty ? unlocked[random(0..<unlocked.count)] : nextTier[random(0..<nextTier.count)]
        }
        let root = mode == .note ? 60 : random(48..<61)
        let midis = mode == .note ? [60 + skill.semitones[0]] : skill.semitones.map { root + $0 }
        let distractors = all.filter { $0.id != skill.id }.map(\.label).shuffled()
        let choiceCount = min(4, max(2, all.count))
        let choices = Array((Array(distractors.prefix(choiceCount - 1)) + [skill.label]).shuffled())
        return EarTrainingQuestion(label: skill.label, skillID: skill.id, mode: mode, tier: skill.tier, midis: midis, choices: choices)
    }
}
