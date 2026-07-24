import Combine
import Foundation

protocol GameProfilePersisting {
    func load() -> GameProfile?
    func save(_ profile: GameProfile)
}

struct UserDefaultsGamePersistence: GameProfilePersisting {
    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, key: String = "stew.games.profile.v1") {
        self.defaults = defaults
        self.key = key
    }

    func load() -> GameProfile? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(GameProfile.self, from: data)
    }

    func save(_ profile: GameProfile) {
        guard let data = try? JSONEncoder().encode(profile) else { return }
        defaults.set(data, forKey: key)
    }
}

@MainActor
final class GameProgressStore: ObservableObject {
    @Published private(set) var profile: GameProfile

    var accountSudokuSink: ((SudokuSession) -> Void)?
    var accountMelodySink: ((MelodyMemorySession) -> Void)?
    var accountLocalChangeSink: (() -> Void)?

    private let persistence: GameProfilePersisting
    private var calendar: Calendar
    private let now: () -> Date
    private let generator: HarmonicSudokuGenerator
    private var guestProfile: GameProfile
    private(set) var isAccountMode = false

    init(
        persistence: GameProfilePersisting = UserDefaultsGamePersistence(),
        calendar: Calendar = .autoupdatingCurrent,
        now: @escaping () -> Date = Date.init,
        generator: HarmonicSudokuGenerator = HarmonicSudokuGenerator()
    ) {
        self.persistence = persistence
        self.calendar = calendar
        self.now = now
        self.generator = generator
        let loaded = persistence.load() ?? GameProfile()
        profile = loaded
        guestProfile = loaded
        reconcile()
    }

    var guestProfileSnapshot: GameProfile { guestProfile }

    var sudoku: HarmonicSudokuStats { profile.sudoku }
    var melody: MelodyMemoryStats { profile.melody }

    func reconcile(for date: Date? = nil) {
        let date = date ?? now()
        let today = dayKey(for: date)
        if let last = profile.sudoku.lastDailyCompletionDay,
           last != today,
           !isYesterday(last, relativeTo: date) {
            profile.sudoku.currentDailyStreak = 0
        }
        if let session = profile.activeDailySudoku, session.puzzle.dayKey != today {
            profile.activeDailySudoku = nil
        }
        save()
    }

    func dailySession(for date: Date? = nil) -> SudokuSession {
        let date = date ?? now()
        reconcile(for: date)
        let key = dayKey(for: date)
        if let existing = profile.activeDailySudoku, existing.puzzle.dayKey == key { return existing }
        let session = SudokuSession(puzzle: generator.daily(dayKey: key))
        profile.activeDailySudoku = session
        save()
        return session
    }

    func practiceSession(difficulty: SudokuDifficulty) -> SudokuSession {
        if let existing = profile.activePracticeSudoku,
           existing.puzzle.difficulty == difficulty,
           !existing.completed {
            return existing
        }
        return newPracticeSession(difficulty: difficulty)
    }

    func newPracticeSession(difficulty: SudokuDifficulty, seed: String = UUID().uuidString) -> SudokuSession {
        let session = SudokuSession(puzzle: generator.practice(difficulty: difficulty, seed: seed))
        profile.activePracticeSudoku = session
        save()
        return session
    }

    func saveSudoku(_ session: SudokuSession) {
        if session.puzzle.mode == .daily { profile.activeDailySudoku = session }
        else { profile.activePracticeSudoku = session }
        save()
    }

    func completeSudoku(_ source: SudokuSession, date: Date? = nil) -> SudokuSession {
        var session = source
        let date = date ?? now()
        session.pause(at: date)
        session.completed = true
        guard !profile.sudoku.completedPuzzleIDs.contains(session.puzzle.id) else {
            saveSudoku(session)
            return session
        }
        profile.sudoku.completedPuzzleIDs.insert(session.puzzle.id)
        profile.sudoku.solvedCount += 1
        if session.hintsUsed == 0 {
            let key = session.puzzle.difficulty.rawValue
            let previous = profile.sudoku.bestUnassistedSeconds[key] ?? .max
            profile.sudoku.bestUnassistedSeconds[key] = min(previous, session.elapsedSeconds)
        }
        if session.puzzle.mode == .daily, let key = session.puzzle.dayKey {
            let alreadyCompleted = profile.sudoku.completedDailyDays.contains(key)
            if !alreadyCompleted {
                if let last = profile.sudoku.lastDailyCompletionDay, isYesterday(last, relativeTo: date) {
                    profile.sudoku.currentDailyStreak += 1
                } else {
                    profile.sudoku.currentDailyStreak = 1
                }
                profile.sudoku.longestDailyStreak = max(
                    profile.sudoku.longestDailyStreak,
                    profile.sudoku.currentDailyStreak
                )
                profile.sudoku.lastDailyCompletionDay = key
                profile.sudoku.completedDailyDays.append(key)
                profile.sudoku.completedDailyDays = Array(profile.sudoku.completedDailyDays.sorted().suffix(120))
            }
        }
        session.completionRecorded = true
        saveSudoku(session)
        if isAccountMode { accountSudokuSink?(session) }
        return session
    }

    func recordMelodyResult(_ session: MelodyMemorySession) {
        profile.melody.gamesPlayed += 1
        profile.melody.highScore = max(profile.melody.highScore, session.score)
        profile.melody.longestSequence = max(profile.melody.longestSequence, session.sequence.count)
        profile.melody.totalCorrectRounds += session.completedRounds
        let key = session.difficulty.rawValue
        profile.melody.bestScores[key] = max(profile.melody.bestScores[key] ?? 0, session.score)
        save()
        if isAccountMode { accountMelodySink?(session) }
    }

    func bestSudokuTime(for difficulty: SudokuDifficulty) -> Int? {
        profile.sudoku.bestUnassistedSeconds[difficulty.rawValue]
    }

    func isDailyComplete(on date: Date? = nil) -> Bool {
        profile.sudoku.completedDailyDays.contains(dayKey(for: date ?? now()))
    }

    func dayKey(for date: Date) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    private func isYesterday(_ key: String, relativeTo date: Date) -> Bool {
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: date) else { return false }
        return dayKey(for: yesterday) == key
    }

    func activateAccountProfile(_ accountProfile: GameProfile) {
        isAccountMode = true
        profile = accountProfile
        reconcile()
    }

    func applyAccountSnapshot(_ snapshot: ProgressSnapshot) {
        let activeDaily = isAccountMode ? profile.activeDailySudoku : nil
        let activePractice = isAccountMode ? profile.activePracticeSudoku : nil
        let sudoku = snapshot.games.sudoku
        let melody = snapshot.games.melody
        var value = GameProfile()
        value.sudoku = HarmonicSudokuStats(
            solvedCount: sudoku.solvedCount,
            currentDailyStreak: sudoku.currentDailyStreak,
            longestDailyStreak: sudoku.longestDailyStreak,
            lastDailyCompletionDay: sudoku.lastDailyCompletionDay,
            completedDailyDays: sudoku.completedDailyDays,
            bestUnassistedSeconds: Dictionary(
                uniqueKeysWithValues: sudoku.bestUnassistedSeconds.map {
                    ($0.key.capitalized, $0.value)
                }
            ),
            completedPuzzleIDs: Set(sudoku.completedPuzzleIDs)
        )
        value.melody = MelodyMemoryStats(
            gamesPlayed: melody.gamesPlayed,
            highScore: melody.highScore,
            longestSequence: melody.longestSequence,
            totalCorrectRounds: melody.totalCorrectRounds,
            bestScores: Dictionary(
                uniqueKeysWithValues: melody.bestScores.map { ($0.key.capitalized, $0.value) }
            )
        )
        value.activeDailySudoku = activeDaily
        value.activePracticeSudoku = activePractice
        isAccountMode = true
        profile = value
        accountLocalChangeSink?()
    }

    func restoreGuestProfile() {
        isAccountMode = false
        profile = guestProfile
        reconcile()
    }

    private func save() {
        if isAccountMode {
            accountLocalChangeSink?()
        } else {
            guestProfile = profile
            persistence.save(profile)
        }
    }
}

enum GameFormatting {
    static func duration(_ seconds: Int) -> String {
        String(format: "%d:%02d", max(0, seconds) / 60, max(0, seconds) % 60)
    }
}
