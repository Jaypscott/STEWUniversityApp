import Combine
import Foundation
import Network
import SwiftData

protocol ProgressAPIProviding: Sendable {
    func fetchProgress() async throws -> ProgressSnapshot
    func sendProgressEvents(_ events: [ProgressEventEnvelope]) async throws -> ProgressBatchResponse
    func importProgress(_ body: ProgressImportBody) async throws -> ProgressImportResponse
    func updateProgressPreferences(dailyGoal: Int?, timeZone: String?) async throws -> ProgressSnapshot
}

struct ProgressSnapshot: Codable, Equatable {
    let revision: Int
    let updatedAt: Date
    let importState: ImportState
    let preferences: SyncedProgressPreferences
    let account: SyncedAccountProgress
    let earTraining: SyncedEarTrainingProgress
    let games: SyncedGameStatistics

    enum ImportState: String, Codable { case awaitingChoice = "awaiting_choice", complete }
}

struct SyncedProgressPreferences: Codable, Equatable {
    let dailyGoal: Int
    let timeZone: String
}

struct SyncedAccountProgress: Codable, Equatable {
    let xp: Int
    let level: Int
    let levelTitle: String
    let xpIntoLevel: Int
    let xpToNextLevel: Int?
}

struct SyncedMasteryProgress: Codable, Equatable {
    let attempts: Int
    let correct: Int
    let score: Double
}

struct SyncedDailyEarProgress: Codable, Equatable {
    let day: String
    let answered: Int
    let correct: Int
    let xpEarned: Int
    let bestCombo: Int
    let goalTarget: Int
    let goalCompleted: Bool
    let challengeKind: String
    let challengeProgress: Int
    let challengeTarget: Int
    let challengeCompleted: Bool
}

struct SyncedEarTrainingProgress: Codable, Equatable {
    let currentStreak: Int
    let longestStreak: Int
    let mastery: [String: SyncedMasteryProgress]
    let achievements: [String]
    let completedGoalDays: [String]
    let today: SyncedDailyEarProgress
}

struct SyncedSudokuStatistics: Codable, Equatable {
    let solvedCount: Int
    let currentDailyStreak: Int
    let longestDailyStreak: Int
    let lastDailyCompletionDay: String?
    let completedDailyDays: [String]
    let bestUnassistedSeconds: [String: Int]
    let completedPuzzleIDs: [String]
}

struct SyncedMelodyStatistics: Codable, Equatable {
    let gamesPlayed: Int
    let highScore: Int
    let longestSequence: Int
    let totalCorrectRounds: Int
    let bestScores: [String: Int]
}

struct SyncedGameStatistics: Codable, Equatable {
    let sudoku: SyncedSudokuStatistics
    let melody: SyncedMelodyStatistics
}

struct EarAnsweredProgressPayload: Codable, Equatable {
    let skillID: String
    let mode: String
    let correct: Bool
}

struct SudokuCompletedProgressPayload: Codable, Equatable {
    let puzzleID: String
    let mode: String
    let difficulty: String
    let dayKey: String?
    let elapsedSeconds: Int
    let mistakes: Int
    let hintsUsed: Int
}

struct MelodyCompletedProgressPayload: Codable, Equatable {
    let difficulty: String
    let score: Int
    let completedRounds: Int
    let longestSequence: Int
}

enum ProgressEventPayload: Equatable {
    case ear(EarAnsweredProgressPayload)
    case sudoku(SudokuCompletedProgressPayload)
    case melody(MelodyCompletedProgressPayload)
}

struct ProgressEventEnvelope: Codable, Equatable {
    let clientEventID: UUID
    let installationID: UUID
    let sessionID: UUID
    let sequenceNumber: Int
    let type: String
    let occurredAt: Date
    let payload: ProgressEventPayload

    private enum CodingKeys: String, CodingKey {
        case clientEventID, installationID, sessionID, sequenceNumber, type, occurredAt, payload
    }

    init(
        clientEventID: UUID = UUID(),
        installationID: UUID,
        sessionID: UUID,
        sequenceNumber: Int,
        type: String,
        occurredAt: Date = .now,
        payload: ProgressEventPayload
    ) {
        self.clientEventID = clientEventID
        self.installationID = installationID
        self.sessionID = sessionID
        self.sequenceNumber = sequenceNumber
        self.type = type
        self.occurredAt = occurredAt
        self.payload = payload
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        clientEventID = try values.decode(UUID.self, forKey: .clientEventID)
        installationID = try values.decode(UUID.self, forKey: .installationID)
        sessionID = try values.decode(UUID.self, forKey: .sessionID)
        sequenceNumber = try values.decode(Int.self, forKey: .sequenceNumber)
        type = try values.decode(String.self, forKey: .type)
        occurredAt = try values.decode(Date.self, forKey: .occurredAt)
        switch type {
        case "ear_answered": payload = .ear(try values.decode(EarAnsweredProgressPayload.self, forKey: .payload))
        case "sudoku_completed": payload = .sudoku(try values.decode(SudokuCompletedProgressPayload.self, forKey: .payload))
        case "melody_completed": payload = .melody(try values.decode(MelodyCompletedProgressPayload.self, forKey: .payload))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type, in: values, debugDescription: "Unsupported progress event type"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(clientEventID, forKey: .clientEventID)
        try values.encode(installationID, forKey: .installationID)
        try values.encode(sessionID, forKey: .sessionID)
        try values.encode(sequenceNumber, forKey: .sequenceNumber)
        try values.encode(type, forKey: .type)
        try values.encode(occurredAt, forKey: .occurredAt)
        switch payload {
        case let .ear(value): try values.encode(value, forKey: .payload)
        case let .sudoku(value): try values.encode(value, forKey: .payload)
        case let .melody(value): try values.encode(value, forKey: .payload)
        }
    }
}

struct ProgressRejectedEvent: Codable, Equatable {
    let clientEventID: UUID
    let code: String
    let message: String
}

struct ProgressBatchResponse: Codable, Equatable {
    let accepted: [UUID]
    let duplicate: [UUID]
    let rejected: [ProgressRejectedEvent]
    let snapshot: ProgressSnapshot
}

struct ProgressImportResponse: Codable, Equatable {
    let applied: Bool
    let snapshot: ProgressSnapshot
}

struct ProgressImportBody: Encodable {
    let strategy: String
    let installationID: UUID
    let timeZone: String
    let legacy: LegacyProgressBody?
}

struct LegacyProgressBody: Encodable {
    let earTraining: LegacyEarTrainingBody
    let sudoku: LegacySudokuBody
    let melody: LegacyMelodyBody
}

struct LegacyEarTrainingBody: Encodable {
    let totalXP: Int
    let currentStreak: Int
    let longestStreak: Int
    let lastGoalCompletionDay: String?
    let dailyGoal: Int
    let mastery: [String: LegacyMasteryBody]
    let achievements: [String]
    let today: LegacyDailyEarBody?
    let completedGoalDays: [String]
}

struct LegacyMasteryBody: Encodable { let attempts: Int; let correct: Int; let score: Double }

struct LegacyDailyEarBody: Encodable {
    let day: String
    let answered: Int
    let correct: Int
    let xpEarned: Int
    let bestCombo: Int
    let challengeKind: String
    let challengeProgress: Int
    let challengeCompleted: Bool
}

struct LegacySudokuBody: Encodable {
    let solvedCount: Int
    let currentDailyStreak: Int
    let longestDailyStreak: Int
    let lastDailyCompletionDay: String?
    let completedDailyDays: [String]
    let bestUnassistedSeconds: [String: Int]
    let completedPuzzleIDs: [String]
}

struct LegacyMelodyBody: Encodable {
    let gamesPlayed: Int
    let highScore: Int
    let longestSequence: Int
    let totalCorrectRounds: Int
    let bestScores: [String: Int]
}

struct ProgressEventsBody: Encodable { let events: [ProgressEventEnvelope] }
struct ProgressPreferencesBody: Encodable { let dailyGoal: Int?; let timeZone: String? }
struct ProgressPreferencesResponse: Decodable { let snapshot: ProgressSnapshot }

@Model
final class PendingProgressEvent {
    @Attribute(.unique) var clientEventID: String
    var userID: String
    var eventData: Data
    var occurredAt: Date
    var attemptCount: Int
    var nextAttemptAt: Date

    init(userID: UUID, event: ProgressEventEnvelope, data: Data) {
        clientEventID = event.clientEventID.uuidString
        self.userID = userID.uuidString
        eventData = data
        occurredAt = event.occurredAt
        attemptCount = 0
        nextAttemptAt = .distantPast
    }
}

@Model
final class CachedAccountProgress {
    @Attribute(.unique) var userID: String
    var localProfileData: Data
    var snapshotData: Data?
    var revision: Int
    var updatedAt: Date
    var lastSuccessfulSync: Date?

    init(userID: UUID, localProfileData: Data) {
        self.userID = userID.uuidString
        self.localProfileData = localProfileData
        snapshotData = nil
        revision = 0
        updatedAt = .now
        lastSuccessfulSync = nil
    }
}

struct LocalAccountProgress: Codable {
    let earTraining: EarTrainingProfile
    let games: GameProfile
}

enum ProgressSyncStatus: Equatable {
    case guest
    case idle
    case syncing
    case offline
    case attention

    var title: String {
        switch self {
        case .guest: "Guest · On this device"
        case .idle: "Synced"
        case .syncing: "Syncing…"
        case .offline: "Offline · Activity saved"
        case .attention: "Sync needs attention"
        }
    }
}

enum AppInstallation {
    private static let key = "stew.account.installation-id.v1"
    static var identifier: UUID {
        if let value = UserDefaults.standard.string(forKey: key), let identifier = UUID(uuidString: value) {
            return identifier
        }
        let identifier = UUID()
        UserDefaults.standard.set(identifier.uuidString, forKey: key)
        return identifier
    }
}

@MainActor
final class ProgressSyncCoordinator: ObservableObject {
    @Published private(set) var status: ProgressSyncStatus = .guest
    @Published private(set) var lastSuccessfulSync: Date?
    @Published private(set) var pendingActivityCount = 0
    @Published private(set) var requiresImportChoice = false
    @Published private(set) var latestSnapshot: ProgressSnapshot?
    @Published private(set) var errorMessage: String?

    private let context: ModelContext
    private let account: AccountSession
    private let earTraining: EarTrainingProgressStore
    private let games: GameProgressStore
    private let client: any ProgressAPIProviding
    private let encoder = BandJSONCoding.encoder()
    private let decoder = BandJSONCoding.decoder()
    private let networkMonitor = NWPathMonitor()
    private let networkQueue = DispatchQueue(label: "com.stewuniversity.progress-network")
    private var accountCancellable: AnyCancellable?
    private var activeUserID: UUID?
    private var earSessionID = UUID()
    private var earSequence = 0
    private var isSyncing = false

    init(
        context: ModelContext,
        account: AccountSession,
        earTraining: EarTrainingProgressStore,
        games: GameProgressStore,
        client: any ProgressAPIProviding = STEWAPIClient.shared
    ) {
        self.context = context
        self.account = account
        self.earTraining = earTraining
        self.games = games
        self.client = client

        earTraining.accountAnswerSink = { [weak self] skillID, mode, correct in
            self?.enqueueEarAnswer(skillID: skillID, mode: mode, correct: correct)
        }
        earTraining.accountDailyGoalSink = { [weak self] goal in
            Task { await self?.updatePreferences(dailyGoal: goal, timeZone: nil) }
        }
        earTraining.accountLocalChangeSink = { [weak self] in self?.persistLocalCache() }
        games.accountSudokuSink = { [weak self] session in self?.enqueueSudoku(session) }
        games.accountMelodySink = { [weak self] session in self?.enqueueMelody(session) }
        games.accountLocalChangeSink = { [weak self] in self?.persistLocalCache() }

        accountCancellable = account.$state.sink { [weak self] state in
            Task { @MainActor in await self?.handleAccountState(state) }
        }
        ProgressPushRefreshHandler.shared.refresh = { [weak self] in
            await self?.synchronize()
        }
        networkMonitor.pathUpdateHandler = { [weak self] path in
            guard path.status == .satisfied else { return }
            Task { @MainActor in await self?.synchronize() }
        }
        networkMonitor.start(queue: networkQueue)
    }

    deinit { networkMonitor.cancel() }

    func handleForeground() async {
        guard activeUserID != nil else { return }
        await BandPushManager.shared.registerForBackgroundUpdates()
        await synchronize()
    }

    func synchronize() async {
        guard activeUserID != nil, !isSyncing, !requiresImportChoice else { return }
        isSyncing = true
        status = .syncing
        errorMessage = nil
        defer { isSyncing = false }
        do {
            let allPending = pendingEvents(readyOnly: false)
            if allPending.isEmpty {
                let snapshot = try await client.fetchProgress()
                try process(snapshot)
            } else if !pendingEvents(readyOnly: true).isEmpty {
                try await uploadPendingEvents()
            } else {
                status = .offline
                refreshPendingCount()
                return
            }
            lastSuccessfulSync = .now
            persistLocalCache()
        } catch {
            status = .offline
            errorMessage = error.localizedDescription
        }
        refreshPendingCount()
        if errorMessage != nil, pendingActivityCount > 0 { status = .attention }
        else if status == .syncing { status = .idle }
    }

    func chooseDeviceProgress() async {
        guard let activeUserID else { return }
        status = .syncing
        do {
            let response = try await client.importProgress(
                ProgressImportBody(
                    strategy: "use_device",
                    installationID: AppInstallation.identifier,
                    timeZone: TimeZone.autoupdatingCurrent.identifier,
                    legacy: legacyBody()
                )
            )
            self.activeUserID = activeUserID
            requiresImportChoice = false
            try process(response.snapshot)
            status = .idle
            lastSuccessfulSync = .now
        } catch {
            status = .attention
            errorMessage = error.localizedDescription
        }
    }

    func chooseAccountProgress() async {
        guard activeUserID != nil else { return }
        status = .syncing
        do {
            let response = try await client.importProgress(
                ProgressImportBody(
                    strategy: "use_account",
                    installationID: AppInstallation.identifier,
                    timeZone: TimeZone.autoupdatingCurrent.identifier,
                    legacy: nil
                )
            )
            requiresImportChoice = false
            try process(response.snapshot)
            status = .idle
            lastSuccessfulSync = .now
        } catch {
            status = .attention
            errorMessage = error.localizedDescription
        }
    }

    func updateTimeZoneToCurrent() async {
        await updatePreferences(dailyGoal: nil, timeZone: TimeZone.autoupdatingCurrent.identifier)
    }

    private func handleAccountState(_ state: AccountAuthState) async {
        switch state {
        case let .signedIn(user):
            if activeUserID != user.id {
                activeUserID = user.id
                earSessionID = UUID()
                earSequence = 0
                loadCache(for: user.id)
            }
            await BandPushManager.shared.registerForBackgroundUpdates()
            await BandPushManager.shared.registerCachedTokenIfAvailable()
            await synchronizeAllowingImportCheck()
        case .signedOut:
            activeUserID = nil
            requiresImportChoice = false
            latestSnapshot = nil
            status = .guest
            errorMessage = nil
            earTraining.restoreGuestProfile()
            games.restoreGuestProfile()
            refreshPendingCount()
        case .restoring, .needsProfile, .failed:
            break
        }
    }

    private func synchronizeAllowingImportCheck() async {
        guard !isSyncing else { return }
        isSyncing = true
        status = .syncing
        defer { isSyncing = false }
        do {
            if latestSnapshot?.importState == .complete,
               !pendingEvents(readyOnly: false).isEmpty {
                if !pendingEvents(readyOnly: true).isEmpty {
                    try await uploadPendingEvents()
                    status = .idle
                    lastSuccessfulSync = .now
                } else {
                    status = .offline
                }
                refreshPendingCount()
                return
            }
            let snapshot = try await client.fetchProgress()
            if snapshot.importState == .awaitingChoice {
                latestSnapshot = snapshot
                requiresImportChoice = true
                status = .attention
            } else {
                requiresImportChoice = false
                try process(snapshot)
                if !pendingEvents(readyOnly: true).isEmpty { try await uploadPendingEvents() }
                status = .idle
                lastSuccessfulSync = .now
            }
        } catch {
            status = .offline
            errorMessage = error.localizedDescription
        }
        refreshPendingCount()
    }

    private func enqueueEarAnswer(skillID: String, mode: EarTrainingMode, correct: Bool) {
        earSequence += 1
        let modeValue: String
        switch mode {
        case .interval: modeValue = "interval"
        case .chord: modeValue = "chord"
        case .note: modeValue = "note"
        }
        enqueue(
            ProgressEventEnvelope(
                installationID: AppInstallation.identifier,
                sessionID: earSessionID,
                sequenceNumber: earSequence,
                type: "ear_answered",
                payload: .ear(
                    EarAnsweredProgressPayload(
                        skillID: skillID,
                        mode: modeValue,
                        correct: correct
                    )
                )
            )
        )
    }

    private func enqueueSudoku(_ session: SudokuSession) {
        enqueue(
            ProgressEventEnvelope(
                installationID: AppInstallation.identifier,
                sessionID: UUID(),
                sequenceNumber: 1,
                type: "sudoku_completed",
                payload: .sudoku(
                    SudokuCompletedProgressPayload(
                        puzzleID: session.puzzle.id,
                        mode: session.puzzle.mode.rawValue.lowercased(),
                        difficulty: session.puzzle.difficulty.rawValue.lowercased(),
                        dayKey: session.puzzle.dayKey,
                        elapsedSeconds: session.elapsedSeconds,
                        mistakes: session.mistakes,
                        hintsUsed: session.hintsUsed
                    )
                )
            )
        )
    }

    private func enqueueMelody(_ session: MelodyMemorySession) {
        enqueue(
            ProgressEventEnvelope(
                installationID: AppInstallation.identifier,
                sessionID: UUID(),
                sequenceNumber: 1,
                type: "melody_completed",
                payload: .melody(
                    MelodyCompletedProgressPayload(
                        difficulty: session.difficulty.rawValue.lowercased(),
                        score: session.score,
                        completedRounds: session.completedRounds,
                        longestSequence: session.sequence.count
                    )
                )
            )
        )
    }

    private func enqueue(_ event: ProgressEventEnvelope) {
        guard let activeUserID, !requiresImportChoice else { return }
        do {
            let data = try encoder.encode(event)
            context.insert(PendingProgressEvent(userID: activeUserID, event: event, data: data))
            try context.save()
            persistLocalCache()
            refreshPendingCount()
            Task { await synchronize() }
        } catch {
            status = .attention
            errorMessage = error.localizedDescription
        }
    }

    private func uploadPendingEvents() async throws {
        let rows = Array(pendingEvents(readyOnly: true).prefix(100))
        guard !rows.isEmpty else { return }
        let events = try rows.map { try decoder.decode(ProgressEventEnvelope.self, from: $0.eventData) }
        do {
            let response = try await client.sendProgressEvents(events)
            let finished = Set((response.accepted + response.duplicate).map(\.uuidString))
            for row in rows where finished.contains(row.clientEventID) { context.delete(row) }
            let rejected = Dictionary(uniqueKeysWithValues: response.rejected.map { ($0.clientEventID.uuidString, $0) })
            for row in rows {
                if let rejection = rejected[row.clientEventID] {
                    row.attemptCount += 1
                    row.nextAttemptAt = retryDate(attempt: row.attemptCount)
                    errorMessage = rejection.message
                }
            }
            try context.save()
            try process(response.snapshot)
        } catch {
            for row in rows {
                row.attemptCount += 1
                row.nextAttemptAt = retryDate(attempt: row.attemptCount)
            }
            try? context.save()
            throw error
        }
    }

    private func process(_ snapshot: ProgressSnapshot) throws {
        guard snapshot.importState == .complete else {
            requiresImportChoice = true
            latestSnapshot = snapshot
            return
        }
        latestSnapshot = snapshot
        earTraining.applyAccountSnapshot(snapshot)
        games.applyAccountSnapshot(snapshot)
        lastSuccessfulSync = .now
        persistLocalCache(snapshot: snapshot)
    }

    private func pendingEvents(readyOnly: Bool) -> [PendingProgressEvent] {
        guard let activeUserID else { return [] }
        let key = activeUserID.uuidString
        let now = Date.now
        let rows = (try? context.fetch(FetchDescriptor<PendingProgressEvent>())) ?? []
        return rows
            .filter { $0.userID == key && (!readyOnly || $0.nextAttemptAt <= now) }
            .sorted { $0.occurredAt < $1.occurredAt }
    }

    private func retryDate(attempt: Int) -> Date {
        let seconds = min(3_600.0, pow(2.0, Double(min(attempt, 10))) * 2.0)
        return .now.addingTimeInterval(seconds)
    }

    private func refreshPendingCount() {
        guard let activeUserID else { pendingActivityCount = 0; return }
        let key = activeUserID.uuidString
        pendingActivityCount = ((try? context.fetch(FetchDescriptor<PendingProgressEvent>())) ?? [])
            .filter { $0.userID == key }.count
    }

    private func loadCache(for userID: UUID) {
        let key = userID.uuidString
        guard let cached = ((try? context.fetch(FetchDescriptor<CachedAccountProgress>())) ?? [])
            .first(where: { $0.userID == key }) else {
            refreshPendingCount()
            return
        }
        if let local = try? decoder.decode(LocalAccountProgress.self, from: cached.localProfileData) {
            earTraining.activateAccountProfile(local.earTraining)
            games.activateAccountProfile(local.games)
        }
        if let data = cached.snapshotData,
           let snapshot = try? decoder.decode(ProgressSnapshot.self, from: data) {
            latestSnapshot = snapshot
            requiresImportChoice = snapshot.importState == .awaitingChoice
        }
        lastSuccessfulSync = cached.lastSuccessfulSync
        refreshPendingCount()
    }

    private func persistLocalCache(snapshot: ProgressSnapshot? = nil) {
        guard let activeUserID else { return }
        let local = LocalAccountProgress(
            earTraining: earTraining.profile,
            games: games.profile
        )
        guard let data = try? encoder.encode(local) else { return }
        let key = activeUserID.uuidString
        let cached = ((try? context.fetch(FetchDescriptor<CachedAccountProgress>())) ?? [])
            .first(where: { $0.userID == key })
            ?? CachedAccountProgress(userID: activeUserID, localProfileData: data)
        if cached.modelContext == nil { context.insert(cached) }
        cached.localProfileData = data
        let value = snapshot ?? latestSnapshot
        if let value, let snapshotData = try? encoder.encode(value) {
            cached.snapshotData = snapshotData
            cached.revision = value.revision
        }
        cached.updatedAt = .now
        cached.lastSuccessfulSync = lastSuccessfulSync
        try? context.save()
    }

    private func legacyBody() -> LegacyProgressBody {
        let ear = earTraining.guestProfileSnapshot
        let game = games.guestProfileSnapshot
        let today = ear.today.map {
            LegacyDailyEarBody(
                day: $0.dayKey,
                answered: $0.answered,
                correct: $0.correct,
                xpEarned: $0.xpEarned,
                bestCombo: $0.bestCombo,
                challengeKind: $0.challenge.kind.rawValue,
                challengeProgress: $0.challenge.progress,
                challengeCompleted: $0.challenge.completed
            )
        }
        return LegacyProgressBody(
            earTraining: LegacyEarTrainingBody(
                totalXP: ear.totalXP,
                currentStreak: ear.currentStreak,
                longestStreak: ear.longestStreak,
                lastGoalCompletionDay: ear.lastGoalCompletionDay,
                dailyGoal: ear.dailyGoal,
                mastery: ear.mastery.mapValues {
                    LegacyMasteryBody(attempts: $0.attempts, correct: $0.correct, score: $0.score)
                },
                achievements: ear.unlockedAchievements.map(\.rawValue).sorted(),
                today: today,
                completedGoalDays: ear.completedGoalDays
            ),
            sudoku: LegacySudokuBody(
                solvedCount: game.sudoku.solvedCount,
                currentDailyStreak: game.sudoku.currentDailyStreak,
                longestDailyStreak: game.sudoku.longestDailyStreak,
                lastDailyCompletionDay: game.sudoku.lastDailyCompletionDay,
                completedDailyDays: game.sudoku.completedDailyDays,
                bestUnassistedSeconds: Dictionary(
                    uniqueKeysWithValues: game.sudoku.bestUnassistedSeconds.map {
                        ($0.key.lowercased(), $0.value)
                    }
                ),
                completedPuzzleIDs: game.sudoku.completedPuzzleIDs.sorted()
            ),
            melody: LegacyMelodyBody(
                gamesPlayed: game.melody.gamesPlayed,
                highScore: game.melody.highScore,
                longestSequence: game.melody.longestSequence,
                totalCorrectRounds: game.melody.totalCorrectRounds,
                bestScores: Dictionary(
                    uniqueKeysWithValues: game.melody.bestScores.map {
                        ($0.key.lowercased(), $0.value)
                    }
                )
            )
        )
    }

    private func updatePreferences(dailyGoal: Int?, timeZone: String?) async {
        guard activeUserID != nil, !requiresImportChoice else { return }
        do {
            let snapshot = try await client.updateProgressPreferences(
                dailyGoal: dailyGoal, timeZone: timeZone
            )
            try process(snapshot)
            status = .idle
        } catch {
            status = .offline
            errorMessage = error.localizedDescription
        }
    }
}
