import XCTest
import AuthenticationServices
import ImageIO
import SwiftData
import UIKit
@testable import STEWUniversity

final class STEWUniversityTests: XCTestCase {
    @MainActor
    func testBandAppleSignInLocksButtonWhileAuthorizationIsPending() {
        let session = BandAuthSession(arguments: ["--ui-testing-band-signed-out"])
        let request = ASAuthorizationAppleIDProvider().createRequest()

        session.configureAppleSignIn(request)

        XCTAssertTrue(session.isWorking)
        XCTAssertNotNil(request.nonce)
        XCTAssertEqual(request.requestedScopes, [.fullName, .email])
    }

    @MainActor
    func testSongwritingStartsEmptyAndCannotSendBlankText() {
        UserDefaults.standard.removeObject(forKey: "stew.songwriting.messages")
        let model = SongwritingViewModel()
        XCTAssertTrue(model.messages.isEmpty)
        XCTAssertFalse(model.canSend)
        model.draft = String(repeating: "a", count: 1201)
        XCTAssertFalse(model.canSend)
    }

    func testNavigationIncludesMobileV1DestinationsOnly() {
        XCTAssertEqual(AppDestination.allCases.map(\.rawValue), ["Account", "Songwriting", "Jam", "Band", "Ear Training", "Visualizer", "Games"])
    }

    func testBandPartKindsAreIndependentFromJamInstruments() {
        XCTAssertEqual(BandPartKind.allCases.map(\.rawValue), ["vocals", "guitar", "bass", "drums", "keys", "other"])
        XCTAssertEqual(BandPartKind.keys.title, "Piano / Keys")
        XCTAssertEqual(BandRole.owner.canManageMembers, true)
        XCTAssertEqual(BandRole.member.canManageMembers, false)
        XCTAssertTrue(BandRole.admin.canManageAppearance)
        XCTAssertFalse(BandRole.member.canManageAppearance)
    }

    func testBandMoodBoardContractsAndAccessibleAccentDecode() throws {
        let json = #"{"id":"30000000-0000-0000-0000-000000000001","band_id":"10000000-0000-0000-0000-000000000001","project_id":null,"referenced_project_id":"20000000-0000-0000-0000-000000000001","author_user_id":"00000000-0000-0000-0000-000000000001","author_display_name":"Jaylon","body":"Current direction","external_url":null,"card_kind":"project","card_size":"wide","is_pinned":true,"pinned_at":"2026-07-14T12:00:00Z","created_at":"2026-07-14T12:00:00Z","edited_at":null,"deleted_at":null,"attachments":[]}"#
        let post = try BandJSONCoding.decoder().decode(BandPost.self, from: Data(json.utf8))
        XCTAssertEqual(post.cardKind, .project)
        XCTAssertEqual(post.cardSize, .wide)
        XCTAssertTrue(post.isPinned)
        XCTAssertNotNil(post.referencedProjectID)

        let light = BandAccentTheme(hex: "#FFFFFF")
        let dark = BandAccentTheme(hex: "#000000")
        XCTAssertTrue(light.usesDarkForeground)
        XCTAssertFalse(dark.usesDarkForeground)
        XCTAssertEqual(BandAccentTheme(hex: "not-a-color").hex, BandAccentTheme.defaultHex)
    }

    func testBandImagePreparationDownsamplesAndNormalizesJPEG() throws {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 3_000, height: 1_500))
        let source = renderer.jpegData(withCompressionQuality: 1) { context in
            UIColor.systemTeal.setFill()
            context.cgContext.fill(CGRect(x: 0, y: 0, width: 3_000, height: 1_500))
        }
        let url = try BandImagePreparation.temporaryJPEG(from: source, maximumPixelSize: 1_024)
        defer { try? FileManager.default.removeItem(at: url) }
        let data = try Data(contentsOf: url)
        let imageSource = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any])
        let width = try XCTUnwrap(properties[kCGImagePropertyPixelWidth] as? Int)
        let height = try XCTUnwrap(properties[kCGImagePropertyPixelHeight] as? Int)
        XCTAssertLessThanOrEqual(max(width, height), 1_024)
        XCTAssertEqual(CGImageSourceGetType(imageSource) as String?, "public.jpeg")
    }

    func testBandProjectAndTrackContractsDecodeSnakeCase() throws {
        let json = #"{"id":"20000000-0000-0000-0000-000000000001","project_id":"21000000-0000-0000-0000-000000000001","name":"Lead Vocal","part_kind":"vocals","custom_part_label":null,"created_by_user_id":"00000000-0000-0000-0000-000000000001","created_at":"2026-07-14T12:00:00Z"}"#
        let track = try BandJSONCoding.decoder().decode(BandTrack.self, from: Data(json.utf8))
        XCTAssertEqual(track.name, "Lead Vocal")
        XCTAssertEqual(track.partKind, .vocals)
        XCTAssertEqual(track.partTitle, "Vocals")

        let invitation = BandPendingInvitation(
            id: UUID(),
            bandID: UUID(),
            createdByUserID: UUID(),
            expiresAt: Date(timeIntervalSince1970: 0),
            status: "pending",
            createdAt: Date(timeIntervalSince1970: 0)
        )
        let encoded = try BandJSONCoding.encoder().encode(invitation)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertNotNil(object["band_id"])
        XCTAssertNotNil(object["created_by_user_id"])
    }

    func testBandUserDecodesProductionURLFields() throws {
        let json = #"{"id":"00000000-0000-0000-0000-000000000001","username":"jaylon","display_name":"Jaylon","is_platform_admin":false,"profile_complete":true,"terms_url":"https://stew-university-backend.onrender.com/legal/terms","privacy_url":"https://stew-university-backend.onrender.com/legal/privacy","support_url":"https://stew-university-backend.onrender.com/support"}"#

        let user = try BandJSONCoding.decoder().decode(BandUser.self, from: Data(json.utf8))

        XCTAssertTrue(user.profileComplete)
        XCTAssertEqual(user.termsURL.path, "/legal/terms")
        XCTAssertEqual(user.privacyURL.path, "/legal/privacy")
        XCTAssertEqual(user.supportURL.path, "/support")
    }

    @MainActor
    func testBandDemoProvidersRepresentEmptyAndPopulatedStates() async {
        let empty = BandStore(provider: DemoBandProvider(populated: false))
        empty.selectedTab = .members
        await empty.load(userID: BandAuthSession.demoUser.id)
        XCTAssertTrue(empty.bands.isEmpty)
        XCTAssertNil(empty.selectedBandID)
        XCTAssertEqual(empty.selectedTab, .home)

        let populated = BandStore(provider: DemoBandProvider(populated: true))
        await populated.load(userID: BandAuthSession.demoUser.id)
        XCTAssertEqual(populated.bands.first?.name, "Golden Hour")
        XCTAssertEqual(populated.projects.first?.title, "Open Skies")
        XCTAssertEqual(populated.members.count, 3)
        XCTAssertEqual(populated.posts.count, 4)
        XCTAssertEqual(populated.posts.first?.cardKind, .note)
        XCTAssertTrue(populated.posts.first?.isPinned == true)
        XCTAssertEqual(populated.featuredProject?.title, "Open Skies")

        populated.selectedTab = .projects
        populated.clear()
        XCTAssertEqual(populated.selectedTab, .home)
    }

    @MainActor
    func testCorrectAnswersAwardComboXPAndWrongAnswerResetsCombo() {
        let date = makeDate(2026, 7, 13)
        let persistence = MemoryEarTrainingPersistence(profile: profile(for: date, challengeCompleted: true))
        let store = makeStore(date: date, persistence: persistence)
        let question = testQuestion()

        XCTAssertEqual(store.answer(question, choice: question.label).xpEarned, 10)
        XCTAssertEqual(store.answer(question, choice: question.label).xpEarned, 12)
        XCTAssertEqual(store.answer(question, choice: question.label).combo, 3)
        XCTAssertEqual(store.answer(question, choice: "Wrong").xpEarned, 0)
        XCTAssertEqual(store.today.currentCombo, 0)
    }

    @MainActor
    func testDailyGoalAwardsOnceAndBuildsStrictStreak() {
        let clock = TestClock(makeDate(2026, 7, 13))
        let persistence = MemoryEarTrainingPersistence(profile: profile(for: clock.date, challengeCompleted: true))
        let store = makeStore(clock: clock, persistence: persistence)
        let question = testQuestion()

        for _ in 0..<4 { XCTAssertFalse(store.answer(question, choice: "Wrong").goalCompleted) }
        XCTAssertTrue(store.answer(question, choice: "Wrong").goalCompleted)
        XCTAssertEqual(store.profile.currentStreak, 1)
        XCTAssertEqual(store.profile.totalXP, 25)
        XCTAssertFalse(store.answer(question, choice: "Wrong").goalCompleted)
        XCTAssertEqual(store.profile.totalXP, 25)

        clock.date = makeDate(2026, 7, 14)
        store.reconcile()
        for _ in 0..<5 { _ = store.answer(question, choice: "Wrong") }
        XCTAssertEqual(store.profile.currentStreak, 2)

        clock.date = makeDate(2026, 7, 16)
        store.reconcile()
        XCTAssertEqual(store.profile.currentStreak, 0)
    }

    @MainActor
    func testMasteryAndListenerLevelThresholds() {
        var mastery = SkillMastery()
        mastery.record(correct: true)
        XCTAssertEqual(mastery.score, 15, accuracy: 0.001)
        mastery.record(correct: false)
        XCTAssertEqual(mastery.score, 12, accuracy: 0.001)
        XCTAssertEqual(ListenerLevel.level(for: 599), .developing)
        XCTAssertEqual(ListenerLevel.level(for: 600), .focused)
        XCTAssertEqual(ListenerLevel.level(for: 3_600), .golden)
    }

    func testAdaptiveTierUnlockRequiresPracticeAndMastery() {
        var profile = EarTrainingProfile()
        for skill in EarTrainingQuestionFactory.skills(for: .chord).filter({ $0.tier == 1 }) {
            profile.mastery[skill.id] = SkillMastery(attempts: 6, correct: 6, score: 75)
        }
        XCTAssertEqual(EarTrainingQuestionFactory.unlockedTier(for: .chord, profile: profile), 2)
    }

    @MainActor
    func testDailyChallengeIsDeterministicAndPersistenceSurvivesReload() {
        XCTAssertEqual(EarTrainingProgressStore.challenge(for: "2026-07-13"), EarTrainingProgressStore.challenge(for: "2026-07-13"))
        let date = makeDate(2026, 7, 13)
        let persistence = MemoryEarTrainingPersistence()
        let store = makeStore(date: date, persistence: persistence)
        store.setDailyGoal(10)
        let reloaded = makeStore(date: date, persistence: persistence)
        XCTAssertEqual(reloaded.profile.dailyGoal, 10)
        XCTAssertEqual(reloaded.today.dayKey, "2026-07-13")
    }

    @MainActor
    func testReminderPermissionAndSchedulingAreInjectable() async {
        let scheduler = MockReminderScheduler()
        let store = EarTrainingProgressStore(
            persistence: MemoryEarTrainingPersistence(),
            reminderScheduler: scheduler,
            calendar: fixedCalendar,
            now: { self.makeDate(2026, 7, 13) }
        )
        await store.setReminder(enabled: true)
        XCTAssertTrue(store.profile.remindersEnabled)
        XCTAssertEqual(scheduler.scheduleCount, 1)
        await store.setReminder(enabled: false)
        XCTAssertEqual(scheduler.cancelCount, 1)
    }

    func testVersionOneProfileMigratesStreakHistoryWithoutLosingProgress() throws {
        let json = #"{"version":1,"totalXP":640,"currentStreak":3,"longestStreak":5,"lastGoalCompletionDay":"2026-07-12","dailyGoal":10,"mastery":{},"unlockedAchievements":[],"remindersEnabled":false,"reminderHour":19,"reminderMinute":0}"#
        let profile = try JSONDecoder().decode(EarTrainingProfile.self, from: Data(json.utf8))
        XCTAssertEqual(profile.version, 2)
        XCTAssertEqual(profile.totalXP, 640)
        XCTAssertEqual(profile.dailyGoal, 10)
        XCTAssertEqual(profile.completedGoalDays, ["2026-07-12"])
    }

    func testCelebrationEventsFollowRequiredOrder() {
        let mastery = MasteryCategoryChange(skillID: "interval.major3", skillLabel: "Major 3rd", previousTitle: "Learning", currentTitle: "Familiar", previousScore: 44, currentScore: 51)
        let outcome = AnswerOutcome(
            correct: true,
            xpEarned: 20,
            combo: 5,
            goalCompleted: true,
            challengeCompleted: true,
            newlyUnlocked: [.comboFive, .perfectFive],
            previousTotalXP: 240,
            currentTotalXP: 315,
            previousLevel: .curious,
            currentLevel: .developing,
            masteryChange: mastery,
            challengeProgress: 3,
            challengeTarget: 3
        )
        var queue = EarTrainingEventQueue()
        queue.enqueue(EarTrainingUXEvent.events(for: outcome))
        XCTAssertEqual(queue.next(), .achievement(.comboFive))
        XCTAssertEqual(queue.next(), .achievement(.perfectFive))
        XCTAssertEqual(queue.next(), .levelUp(.developing))
        XCTAssertEqual(queue.next(), .mastery(mastery))
        XCTAssertEqual(queue.next(), .results)
        XCTAssertNil(queue.next())
    }

    func testIncorrectAnswerDoesNotPresentMasteryCelebration() {
        let regression = MasteryCategoryChange(
            skillID: "interval.perfect5",
            skillLabel: "Perfect 5th",
            previousTitle: "Learning",
            currentTitle: "Beginner",
            previousScore: 21,
            currentScore: 16.8
        )
        let outcome = AnswerOutcome(
            correct: false,
            xpEarned: 0,
            combo: 0,
            goalCompleted: false,
            challengeCompleted: false,
            newlyUnlocked: [],
            previousTotalXP: 100,
            currentTotalXP: 100,
            previousLevel: .curious,
            currentLevel: .curious,
            masteryChange: regression,
            challengeProgress: 0,
            challengeTarget: 3
        )

        XCTAssertTrue(EarTrainingUXEvent.events(for: outcome).isEmpty)
    }

    func testFiveCorrectAchievementHasUnambiguousName() {
        XCTAssertEqual(AchievementID.perfectFive.title, "Five in a Row")
        XCTAssertEqual(AchievementID.perfectFive.detail, "Get five answers right in a row.")
    }

    func testHarmonicSudokuIsDeterministicValidAndUnique() {
        let generator = HarmonicSudokuGenerator()
        let first = generator.daily(dayKey: "2026-07-13")
        let second = generator.daily(dayKey: "2026-07-13")
        XCTAssertEqual(first, second)
        XCTAssertTrue(HarmonicSudokuGenerator.isValid(solution: first.solution))
        XCTAssertEqual(HarmonicSudokuGenerator.solutionCount(for: first.givens), 1)
        XCTAssertGreaterThanOrEqual(first.givens.compactMap { $0 }.count, SudokuDifficulty.medium.clueCount)

        for difficulty in SudokuDifficulty.allCases {
            let puzzle = generator.practice(difficulty: difficulty, seed: "test-\(difficulty.rawValue)")
            XCTAssertTrue(HarmonicSudokuGenerator.isValid(solution: puzzle.solution))
            XCTAssertEqual(HarmonicSudokuGenerator.solutionCount(for: puzzle.givens), 1)
            XCTAssertGreaterThanOrEqual(puzzle.givens.compactMap { $0 }.count, difficulty.clueCount)
        }
    }

    func testHarmonicPalettesCoverAllKeysAndColorChords() {
        XCTAssertEqual(HarmonicPalette.keyNames.count, 12)
        for keyIndex in HarmonicPalette.keyNames.indices {
            let palette = HarmonicPalette(keyIndex: keyIndex)
            XCTAssertEqual(palette.chords.count, 9)
            XCTAssertEqual(Set(palette.chords.map(\.name)).count, 9)
            XCTAssertTrue(palette.chords.allSatisfy { $0.midiNotes.count == 3 })
        }
        let cMajor = HarmonicPalette(keyIndex: 0)
        XCTAssertEqual(cMajor.chord(for: .secondaryDominant).name, "D")
        XCTAssertEqual(cMajor.chord(for: .borrowedMinorSubdominant).name, "Fm")
        XCTAssertEqual(cMajor.chord(for: .leadingTone).name, "B°")
    }

    func testSudokuUndoPreservesRecordedMistakesAndHints() {
        let puzzle = HarmonicSudokuGenerator().practice(difficulty: .easy, seed: "undo")
        var session = SudokuSession(puzzle: puzzle)
        session.pushUndo()
        session.mistakes = 1
        session.hintsUsed = 1
        session.entries[0] = puzzle.solution[0]
        session.undo()
        XCTAssertEqual(session.entries, puzzle.givens)
        XCTAssertEqual(session.mistakes, 1)
        XCTAssertEqual(session.hintsUsed, 1)
    }

    @MainActor
    func testGameProgressPersistsDailyStreakAndUnassistedBestTime() {
        let clock = TestClock(makeDate(2026, 7, 13))
        let persistence = MemoryGamePersistence()
        let store = GameProgressStore(persistence: persistence, calendar: fixedCalendar, now: { clock.date })
        var first = store.dailySession()
        first.entries = first.puzzle.solution.map(Optional.some)
        first.elapsedSeconds = 125
        _ = store.completeSudoku(first)
        XCTAssertEqual(store.sudoku.currentDailyStreak, 1)
        XCTAssertEqual(store.bestSudokuTime(for: .medium), 125)

        clock.date = makeDate(2026, 7, 14)
        var second = store.dailySession()
        second.entries = second.puzzle.solution.map(Optional.some)
        second.elapsedSeconds = 140
        second.hintsUsed = 1
        _ = store.completeSudoku(second)
        XCTAssertEqual(store.sudoku.currentDailyStreak, 2)
        XCTAssertEqual(store.bestSudokuTime(for: .medium), 125)

        let reloaded = GameProgressStore(persistence: persistence, calendar: fixedCalendar, now: { clock.date })
        XCTAssertEqual(reloaded.sudoku.solvedCount, 2)
        XCTAssertEqual(reloaded.sudoku.longestDailyStreak, 2)
    }

    func testMelodyMemoryGrowthReplayScoringAndHearts() {
        let generator = SequenceMelodyGenerator([60, 62, 64, 67, 69])
        var session = MelodyMemorySession(difficulty: .easy, generator: generator)
        XCTAssertEqual(session.sequence, [60, 62, 64])
        XCTAssertTrue(session.useReplay())
        XCTAssertFalse(session.useReplay())
        XCTAssertEqual(session.submit(60), .correctNote)
        XCTAssertEqual(session.submit(62), .correctNote)
        XCTAssertEqual(session.submit(64), .roundComplete(points: 15))
        XCTAssertEqual(session.score, 15)
        session.advance(using: generator)
        XCTAssertEqual(session.sequence, [60, 62, 64, 67])
        XCTAssertFalse(session.replayUsedThisRound)
        XCTAssertEqual(session.submit(69), .retry)
        XCTAssertEqual(session.hearts, 2)
        XCTAssertEqual(session.submit(69), .retry)
        XCTAssertEqual(session.submit(69), .gameOver)
        XCTAssertEqual(session.hearts, 0)
    }

    func testMelodyGeneratorPreventsThreeIdenticalNotes() {
        let generator = RandomMelodyNoteGenerator()
        for _ in 0..<100 {
            XCTAssertNotEqual(generator.nextNote(from: [60, 62], sequence: [60, 60]), 60)
        }
    }

    func testCorruptedGameProfileRecoversSafely() {
        let suite = "stew.games.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set(Data("not-json".utf8), forKey: "profile")
        let persistence = UserDefaultsGamePersistence(defaults: defaults, key: "profile")
        XCTAssertNil(persistence.load())
        defaults.removePersistentDomain(forName: suite)
    }

    func testJamInstrumentsAndRemoteTrackContractDecode() throws {
        XCTAssertEqual(
            JamInstrument.allCases.map(\.title),
            ["Guitar", "Bass", "Drums", "Piano / Keys", "Vocals"]
        )

        let json = #"""
        {
          "id": "midnight-pocket",
          "title": "Midnight Pocket",
          "supported_instruments": ["guitar", "keys"],
          "genre": "Neo-Soul",
          "musical_key": "E minor",
          "bpm": 82,
          "duration": 252,
          "difficulty": "developing",
          "practice_prompt": "Use only three notes for the first chorus.",
          "artwork_url": "https://media.example.com/artwork/midnight-pocket.jpg",
          "audio_url": "https://media.example.com/tracks/midnight-pocket.m4a"
        }
        """#
        let track = try JSONDecoder().decode(JamTrack.self, from: Data(json.utf8))

        XCTAssertEqual(track.id, "midnight-pocket")
        XCTAssertEqual(track.supportedInstruments, [.guitar, .keys])
        XCTAssertEqual(track.musicalKey, "E minor")
        XCTAssertEqual(track.bpm, 82)
        XCTAssertEqual(track.duration, 252)
        XCTAssertEqual(track.difficulty, .developing)
        XCTAssertEqual(track.audioURL.host(), "media.example.com")
    }

    @MainActor
    func testJamCatalogLoadsEmptyAndFiltersByInstrument() async {
        let emptyModel = JamViewModel(provider: EmptyJamCatalogProvider())
        await emptyModel.loadIfNeeded()
        XCTAssertEqual(emptyModel.state, .loaded([]))

        let guitarTrack = makeJamTrack(id: "guitar-groove", instruments: [.guitar])
        let rhythmTrack = makeJamTrack(id: "rhythm-groove", instruments: [.bass, .drums])
        let model = JamViewModel(provider: StubJamCatalogProvider(tracks: [guitarTrack, rhythmTrack]))
        await model.loadIfNeeded()

        XCTAssertEqual(model.tracks(for: .guitar), [guitarTrack])
        XCTAssertEqual(model.tracks(for: .bass), [rhythmTrack])
        XCTAssertTrue(model.tracks(for: .vocals).isEmpty)
    }

    @MainActor
    func testJamCatalogFailureCanRetry() async {
        let track = makeJamTrack(id: "retry-groove", instruments: [.drums])
        let provider = RetryJamCatalogProvider(track: track)
        let model = JamViewModel(provider: provider)

        await model.loadIfNeeded()
        guard case let .failed(message) = model.state else {
            return XCTFail("Expected a retryable Jam catalog failure")
        }
        XCTAssertTrue(message.contains("try again"))

        await model.retry()
        XCTAssertEqual(model.state, .loaded([track]))
        let requestCount = await provider.requestCount
        XCTAssertEqual(requestCount, 2)
    }

    @MainActor
    func testGoalCompletionRecordsRecentDayForCalendar() {
        let date = makeDate(2026, 7, 13)
        let persistence = MemoryEarTrainingPersistence(profile: profile(for: date, challengeCompleted: true))
        let store = makeStore(date: date, persistence: persistence)
        for _ in 0..<5 { _ = store.answer(testQuestion(), choice: "Wrong") }
        XCTAssertEqual(store.profile.completedGoalDays, ["2026-07-13"])
        XCTAssertEqual(store.weekDayKeys().count, 7)
    }

    func testProgressEventEncodesStableIdentifiersAndTypedPayload() throws {
        let clientEventID = UUID()
        let installationID = UUID()
        let sessionID = UUID()
        let event = ProgressEventEnvelope(
            clientEventID: clientEventID,
            installationID: installationID,
            sessionID: sessionID,
            sequenceNumber: 3,
            type: "ear_answered",
            occurredAt: Date(timeIntervalSince1970: 100),
            payload: .ear(
                EarAnsweredProgressPayload(
                    skillID: "interval.major3", mode: "interval", correct: true
                )
            )
        )
        let data = try BandJSONCoding.encoder().encode(event)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["client_event_id"] as? String, clientEventID.uuidString)
        XCTAssertEqual(object["installation_id"] as? String, installationID.uuidString)
        XCTAssertEqual(object["session_id"] as? String, sessionID.uuidString)
        XCTAssertEqual(object["sequence_number"] as? Int, 3)
        XCTAssertEqual(object["type"] as? String, "ear_answered")
        let payload = try XCTUnwrap(object["payload"] as? [String: Any])
        XCTAssertEqual(payload["skill_id"] as? String, "interval.major3")
        XCTAssertEqual(payload["mode"] as? String, "interval")
    }

    @MainActor
    func testAccountProgressDoesNotOverwriteIndependentGuestProfile() {
        var guest = EarTrainingProfile()
        guest.totalXP = 40
        let persistence = MemoryEarTrainingPersistence(profile: guest)
        let store = EarTrainingProgressStore(
            persistence: persistence,
            reminderScheduler: MockReminderScheduler(),
            calendar: fixedCalendar,
            now: { self.makeDate(2026, 7, 20) }
        )
        var accountProfile = guest
        accountProfile.totalXP = 900
        store.activateAccountProfile(accountProfile)
        XCTAssertEqual(store.profile.totalXP, 900)

        _ = store.answer(testQuestion(), choice: "Major 3rd")
        XCTAssertEqual(persistence.profile?.totalXP, 40)

        store.restoreGuestProfile()
        XCTAssertEqual(store.profile.totalXP, 40)
        XCTAssertFalse(store.isAccountMode)
    }

    @MainActor
    func testServerSnapshotReconcilesEarTrainingAndCompletedGameStatistics() {
        let ear = EarTrainingProgressStore(
            persistence: MemoryEarTrainingPersistence(),
            reminderScheduler: MockReminderScheduler(),
            calendar: fixedCalendar,
            now: { self.makeDate(2026, 7, 20) }
        )
        let games = GameProgressStore(
            persistence: MemoryGamePersistence(),
            calendar: fixedCalendar,
            now: { self.makeDate(2026, 7, 20) }
        )
        let snapshot = makeProgressSnapshot(xp: 640)
        ear.applyAccountSnapshot(snapshot)
        games.applyAccountSnapshot(snapshot)

        XCTAssertEqual(ear.profile.totalXP, 640)
        XCTAssertEqual(ear.profile.mastery["interval.major3"]?.attempts, 8)
        XCTAssertEqual(ear.profile.completedGoalDays, ["2026-07-19", "2026-07-20"])
        XCTAssertEqual(games.sudoku.solvedCount, 4)
        XCTAssertEqual(games.bestSudokuTime(for: .medium), 88)
        XCTAssertEqual(games.melody.gamesPlayed, 5)
        XCTAssertEqual(games.melody.highScore, 900)
    }

    @MainActor
    func testOfflineAccountEventRemainsInDurableOutboxAndLogoutRestoresGuest() async throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: PendingProgressEvent.self,
            CachedAccountProgress.self,
            configurations: configuration
        )
        let context = ModelContext(container)
        var guest = EarTrainingProfile()
        guest.totalXP = 25
        let ear = EarTrainingProgressStore(
            persistence: MemoryEarTrainingPersistence(profile: guest),
            reminderScheduler: MockReminderScheduler(),
            calendar: fixedCalendar,
            now: { self.makeDate(2026, 7, 20) }
        )
        let games = GameProgressStore(
            persistence: MemoryGamePersistence(),
            calendar: fixedCalendar,
            now: { self.makeDate(2026, 7, 20) }
        )
        let account = AccountSession(arguments: ["--ui-testing-band-demo"])
        let coordinator = ProgressSyncCoordinator(
            context: context,
            account: account,
            earTraining: ear,
            games: games,
            client: OfflineProgressAPI(snapshot: makeProgressSnapshot(xp: 100))
        )
        await Task.yield()
        await coordinator.synchronize()
        XCTAssertTrue(ear.isAccountMode)

        _ = ear.answer(testQuestion(), choice: "Major 3rd")
        try await Task.sleep(for: .milliseconds(150))
        let pending = try context.fetch(FetchDescriptor<PendingProgressEvent>())
        XCTAssertEqual(pending.count, 1)
        XCTAssertGreaterThanOrEqual(pending[0].attemptCount, 1)

        await account.logout()
        await Task.yield()
        XCTAssertEqual(ear.profile.totalXP, 25)
        XCTAssertFalse(ear.isAccountMode)
    }

    private func makeProgressSnapshot(xp: Int) -> ProgressSnapshot {
        ProgressSnapshot(
            revision: 8,
            updatedAt: Date(timeIntervalSince1970: 100),
            importState: .complete,
            preferences: SyncedProgressPreferences(dailyGoal: 5, timeZone: "America/New_York"),
            account: SyncedAccountProgress(
                xp: xp,
                level: 3,
                levelTitle: "Focused Listener",
                xpIntoLevel: 40,
                xpToNextLevel: 560
            ),
            earTraining: SyncedEarTrainingProgress(
                currentStreak: 2,
                longestStreak: 7,
                mastery: [
                    "interval.major3": SyncedMasteryProgress(attempts: 8, correct: 7, score: 72)
                ],
                achievements: ["firstCorrect", "firstGoal"],
                completedGoalDays: ["2026-07-19", "2026-07-20"],
                today: SyncedDailyEarProgress(
                    day: "2026-07-20",
                    answered: 5,
                    correct: 4,
                    xpEarned: 79,
                    bestCombo: 3,
                    goalTarget: 5,
                    goalCompleted: true,
                    challengeKind: "comboThree",
                    challengeProgress: 3,
                    challengeTarget: 3,
                    challengeCompleted: true
                )
            ),
            games: SyncedGameStatistics(
                sudoku: SyncedSudokuStatistics(
                    solvedCount: 4,
                    currentDailyStreak: 2,
                    longestDailyStreak: 3,
                    lastDailyCompletionDay: "2026-07-20",
                    completedDailyDays: ["2026-07-19", "2026-07-20"],
                    bestUnassistedSeconds: ["medium": 88],
                    completedPuzzleIDs: ["p1", "p2", "p3", "p4"]
                ),
                melody: SyncedMelodyStatistics(
                    gamesPlayed: 5,
                    highScore: 900,
                    longestSequence: 11,
                    totalCorrectRounds: 40,
                    bestScores: ["hard": 900]
                )
            )
        )
    }

    private var fixedCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func makeDate(_ year: Int, _ month: Int, _ day: Int) -> Date {
        fixedCalendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    @MainActor
    private func profile(for date: Date, challengeCompleted: Bool) -> EarTrainingProfile {
        let key = String(format: "%04d-%02d-%02d", fixedCalendar.component(.year, from: date), fixedCalendar.component(.month, from: date), fixedCalendar.component(.day, from: date))
        var challenge = EarTrainingProgressStore.challenge(for: key)
        challenge.completed = challengeCompleted
        var profile = EarTrainingProfile()
        profile.today = DailyPracticeRecord(dayKey: key, challenge: challenge)
        return profile
    }

    @MainActor
    private func makeStore(date: Date, persistence: MemoryEarTrainingPersistence) -> EarTrainingProgressStore {
        EarTrainingProgressStore(persistence: persistence, reminderScheduler: MockReminderScheduler(), calendar: fixedCalendar, now: { date })
    }

    @MainActor
    private func makeStore(clock: TestClock, persistence: MemoryEarTrainingPersistence) -> EarTrainingProgressStore {
        EarTrainingProgressStore(persistence: persistence, reminderScheduler: MockReminderScheduler(), calendar: fixedCalendar, now: { clock.date })
    }

    private func testQuestion() -> EarTrainingQuestion {
        EarTrainingQuestion(label: "Major 3rd", skillID: "interval.major3", mode: .interval, tier: 1, midis: [60, 64], choices: ["Major 3rd", "Wrong"])
    }

    private func makeJamTrack(id: String, instruments: [JamInstrument]) -> JamTrack {
        JamTrack(
            id: id,
            title: "Test Groove",
            supportedInstruments: instruments,
            genre: "Funk",
            musicalKey: "A minor",
            bpm: 96,
            duration: 180,
            difficulty: .beginner,
            practicePrompt: "Stay in the pocket.",
            artworkURL: nil,
            audioURL: URL(string: "https://media.example.com/tracks/\(id).m4a")!
        )
    }
}

private struct StubJamCatalogProvider: JamCatalogProviding {
    let tracks: [JamTrack]
    func fetchTracks() async throws -> [JamTrack] { tracks }
}

private struct OfflineProgressAPI: ProgressAPIProviding {
    let snapshot: ProgressSnapshot

    func fetchProgress() async throws -> ProgressSnapshot { snapshot }
    func sendProgressEvents(_ events: [ProgressEventEnvelope]) async throws -> ProgressBatchResponse {
        throw URLError(.notConnectedToInternet)
    }
    func importProgress(_ body: ProgressImportBody) async throws -> ProgressImportResponse {
        ProgressImportResponse(applied: true, snapshot: snapshot)
    }
    func updateProgressPreferences(dailyGoal: Int?, timeZone: String?) async throws -> ProgressSnapshot {
        snapshot
    }
}

private enum TestJamCatalogError: Error {
    case unavailable
}

private actor RetryJamCatalogProvider: JamCatalogProviding {
    let track: JamTrack
    private(set) var requestCount = 0

    init(track: JamTrack) {
        self.track = track
    }

    func fetchTracks() async throws -> [JamTrack] {
        requestCount += 1
        if requestCount == 1 { throw TestJamCatalogError.unavailable }
        return [track]
    }
}

private final class TestClock {
    var date: Date
    init(_ date: Date) { self.date = date }
}

private final class MemoryEarTrainingPersistence: EarTrainingProfilePersisting {
    var profile: EarTrainingProfile?
    init(profile: EarTrainingProfile? = nil) { self.profile = profile }
    func load() -> EarTrainingProfile? { profile }
    func save(_ profile: EarTrainingProfile) { self.profile = profile }
}

private final class MemoryGamePersistence: GameProfilePersisting {
    var profile: GameProfile?
    init(profile: GameProfile? = nil) { self.profile = profile }
    func load() -> GameProfile? { profile }
    func save(_ profile: GameProfile) { self.profile = profile }
}

private final class SequenceMelodyGenerator: MelodyNoteGenerating {
    private let notes: [Int]
    private var index = 0
    init(_ notes: [Int]) { self.notes = notes }
    func nextNote(from pool: [Int], sequence: [Int]) -> Int {
        defer { index += 1 }
        return notes[index % notes.count]
    }
}

@MainActor
private final class MockReminderScheduler: EarTrainingReminderScheduling {
    var authorizationAllowed = true
    var scheduleCount = 0
    var cancelCount = 0
    func requestAuthorization() async -> Bool { authorizationAllowed }
    func scheduleNext(hour: Int, minute: Int, now: Date, calendar: Calendar) async { scheduleCount += 1 }
    func cancel() { cancelCount += 1 }
}
