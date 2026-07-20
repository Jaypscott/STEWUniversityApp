import SwiftUI
import UIKit

struct EarTrainingView: View {
    @EnvironmentObject private var progress: EarTrainingProgressStore
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var mode: EarTrainingMode = .interval
    @State private var question: EarTrainingQuestion?
    @State private var answeredChoice: String?
    @State private var lastOutcome: AnswerOutcome?
    @State private var explanation = "Choose an answer to reveal a listening tip."
    @State private var loadingExplanation = false
    @State private var animatingExplanation = false
    @State private var showingSettings = false
    @State private var showingAchievements = false
    @State private var showingMastery = false
    @State private var showingResults = false
    @State private var showingStreak = false
    @State private var showingChallenge = false
    @State private var activeEvent: EarTrainingUXEvent?
    @State private var eventQueue = EarTrainingEventQueue()
    @State private var challengeBannerVisible = false
    @State private var isPlayingQuestion = false
    @State private var nextQuestionVisible = false
    @State private var displayedXP = 0
    @State private var floatingXP: Int?
    @State private var xpFloatVisible = false
    @State private var comboPulse = false
    @State private var shakeTrigger: CGFloat = 0
    @State private var sessionAnswered = 0
    @State private var sessionCorrect = 0
    @State private var sessionXP = 0
    @State private var sessionBestCombo = 0
    @State private var feedbackPulse = 0
    @StateObject private var player = PianoSamplePlayer()

    var body: some View {
        ZStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    header
                    if horizontalSizeClass == .regular && !dynamicTypeSize.isAccessibilitySize {
                        HStack(alignment: .top, spacing: 18) {
                            VStack(spacing: 16) {
                                dailyProgressCard
                                levelCard
                                challengeCard
                                masteryCard
                            }
                            .frame(maxWidth: 430)

                            VStack(spacing: 16) {
                                exercisePicker
                                exerciseCard
                                listeningTipCard
                            }
                            .frame(maxWidth: .infinity)
                        }
                    } else {
                        dailyProgressCard
                        levelCard
                        exercisePicker
                        exerciseCard
                        challengeCard
                        masteryCard
                        listeningTipCard
                    }
                }
                .padding(18)
                .adaptiveContentWidth()
            }
            .disabled(activeEvent != nil)

            if challengeBannerVisible {
                VStack {
                    Label("Daily challenge complete · +30 XP", systemImage: "star.fill")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 16).frame(minHeight: 48)
                        .background(.regularMaterial, in: Capsule())
                        .overlay { Capsule().stroke(STEWTheme.gold.opacity(0.6), lineWidth: 1) }
                        .foregroundStyle(STEWTheme.gold)
                        .accessibilityIdentifier("challenge-complete-banner")
                    Spacer()
                }
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(2)
            }

            if let activeEvent {
                celebration(for: activeEvent).zIndex(3)
            }
        }
        .background(Color(.systemBackground))
        .onAppear {
            progress.reconcile()
            displayedXP = progress.profile.totalXP
            if question == nil { loadQuestion(for: mode) }
            if ProcessInfo.processInfo.arguments.contains("--ui-testing-show-achievement"), activeEvent == nil {
                activeEvent = .achievement(.firstCorrect)
            }
        }
        .sheet(isPresented: $showingSettings) { EarTrainingSettingsView() }
        .sheet(isPresented: $showingAchievements, onDismiss: resumeCelebrationQueue) { AchievementsView() }
        .sheet(isPresented: $showingMastery) { MasteryView() }
        .sheet(isPresented: $showingStreak) { StreakDetailView() }
        .sheet(isPresented: $showingChallenge) { ChallengeDetailView() }
        .sheet(isPresented: $showingResults) {
            SessionResultsView(
                answered: sessionAnswered,
                correct: sessionCorrect,
                xp: sessionXP,
                bestCombo: sessionBestCombo,
                challengeCompleted: progress.today.challenge.completed,
                achievements: lastOutcome?.newlyUnlocked ?? []
            ) {
                showingResults = false
                sessionAnswered = 0
                sessionCorrect = 0
                sessionXP = 0
                sessionBestCombo = 0
                loadQuestion(for: mode)
            }
        }
        .sensoryFeedback(lastOutcome?.correct == true ? .success : .error, trigger: feedbackPulse)
        .sensoryFeedback(.success, trigger: activeEvent?.id)
        .accessibilityIdentifier("ear-training-screen")
    }

    private var exercisePicker: some View {
        Picker("Exercise type", selection: $mode) {
            ForEach(EarTrainingMode.allCases) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
        .onChange(of: mode) { _, value in loadQuestion(for: value) }
    }

    @ViewBuilder
    private func celebration(for event: EarTrainingUXEvent) -> some View {
        switch event {
        case let .achievement(achievement):
            AchievementPopupView(
                achievement: achievement,
                reduceMotion: reduceMotion,
                continueAction: completeActiveCelebration,
                viewAchievements: { showingAchievements = true }
            )
        case .levelUp, .mastery:
            MilestonePopupView(event: event, continueAction: completeActiveCelebration)
        case .results:
            EmptyView()
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("EAR TRAINING")
                    .font(.caption.weight(.medium))
                    .tracking(1.5)
                    .foregroundStyle(.secondary)
                Text("Daily Ear Workout").font(.title.weight(.light))
            }
            Spacer()
            Button { showingStreak = true } label: {
                Label("\(progress.profile.currentStreak) day streak", systemImage: "flame.fill")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(progress.profile.currentStreak > 0 ? STEWTheme.gold : .secondary)
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Current streak, \(progress.profile.currentStreak) days. Show streak details")
        }
    }

    private var dailyProgressCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Today’s goal").font(.headline.weight(.regular))
                    Text(progress.today.goalRewardAwarded ? "Complete — keep practicing" : "\(progress.today.answered) of \(progress.profile.dailyGoal) questions")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Button { showingSettings = true } label: { Image(systemName: "slider.horizontal.3") }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.circle)
                    .accessibilityLabel("Ear training settings")
            }
            ProgressView(value: progress.goalProgress).tint(STEWTheme.gold)
                .animation(reduceMotion ? nil : .smooth(duration: 0.55), value: progress.goalProgress)
            HStack {
                Label("Best: \(progress.profile.longestStreak) days", systemImage: "calendar")
                Spacer()
                Button("Achievements") { showingAchievements = true }.font(.subheadline)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .stewSurface()
    }

    private var levelCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Level \(progress.level.number) · \(progress.level.rawValue)").font(.headline.weight(.regular))
                    if let next = progress.level.next {
                        Text("\(next.minimumXP - progress.profile.totalXP) XP to \(next.rawValue)")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("Highest listener level reached").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Text("\(displayedXP) XP")
                    .font(.subheadline.weight(.medium).monospacedDigit())
                    .contentTransition(.numericText(value: Double(displayedXP)))
            }
            ProgressView(value: animatedLevelProgress).tint(STEWTheme.gold)
                .animation(reduceMotion ? nil : .smooth(duration: 0.55), value: animatedLevelProgress)
        }
        .stewSurface()
    }

    private var exerciseCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(roundLabel).font(.caption.weight(.medium)).foregroundStyle(.secondary)
                Spacer()
                if progress.today.currentCombo > 1 {
                    Label("Combo ×\(progress.today.currentCombo)", systemImage: "bolt.fill")
                        .font(.caption.weight(.semibold)).foregroundStyle(STEWTheme.gold)
                        .scaleEffect(comboPulse ? 1.16 : 1)
                        .shadow(color: comboPulse ? STEWTheme.gold.opacity(0.45) : .clear, radius: 8)
                        .transition(.scale.combined(with: .opacity))
                }
            }

            Text(prompt).font(.body.weight(.light))

            Button { playQuestion() } label: {
                Label(isPlayingQuestion ? "Listening…" : (answeredChoice == nil ? "Play" : "Play Again"), systemImage: isPlayingQuestion ? "waveform" : "play.fill")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .tint(STEWTheme.ink)
            .disabled(isPlayingQuestion)

            Text("Choose an answer").font(.headline.weight(.regular))
            LazyVGrid(columns: [.init(.flexible()), .init(.flexible())], spacing: 10) {
                ForEach(question?.choices ?? [], id: \.self) { choice in
                    Button { answer(choice) } label: {
                        HStack {
                            Text(choice)
                            if let symbol = answerSymbol(for: choice) {
                                Image(systemName: symbol)
                                    .transition(.symbolEffect(.drawOn.byLayer))
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 48)
                    }
                    .buttonStyle(.bordered)
                    .tint(answerColor(for: choice))
                    .disabled(answeredChoice != nil || isPlayingQuestion)
                    .modifier(ShakeEffect(animatableData: choice == answeredChoice && lastOutcome?.correct == false ? shakeTrigger : 0))
                    .accessibilityIdentifier("ear-answer-\(choice)")
                    .accessibilityLabel(answerAccessibilityLabel(for: choice))
                }
            }
            .overlay(alignment: .topTrailing) {
                if let floatingXP {
                    Text("+\(floatingXP) XP")
                        .font(.headline.weight(.semibold)).foregroundStyle(STEWTheme.gold)
                        .offset(y: xpFloatVisible ? -38 : 0)
                        .opacity(xpFloatVisible ? 0 : 1)
                        .accessibilityHidden(true)
                }
            }

            if let outcome = lastOutcome, answeredChoice != nil {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label(outcome.correct ? "Correct" : "Not quite", systemImage: outcome.correct ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .font(.headline)
                            .foregroundStyle(outcome.correct ? .green : .orange)
                        Spacer()
                        if outcome.xpEarned > 0 {
                            Text("+\(outcome.xpEarned) XP").font(.subheadline.weight(.semibold)).foregroundStyle(STEWTheme.gold)
                        }
                    }
                    Text(outcome.correct ? "You identified \(question?.label ?? "the sound")." : "The answer was \(question?.label ?? "this sound").")
                        .font(.subheadline).foregroundStyle(.secondary)
                    if outcome.challengeCompleted {
                        Label("Daily challenge complete · +30 XP", systemImage: "star.fill")
                            .font(.subheadline.weight(.medium)).foregroundStyle(STEWTheme.gold)
                    }
                    if nextQuestionVisible {
                        Button("Next Question") { loadQuestion(for: mode) }
                            .buttonStyle(.borderedProminent)
                            .tint(STEWTheme.ink)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .transition(.opacity.combined(with: reduceMotion ? .identity : .move(edge: .bottom)))
            }
        }
        .stewSurface()
    }

    private var challengeCard: some View {
        let challenge = progress.today.challenge
        return Button { showingChallenge = true } label: {
            VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Daily challenge", systemImage: challenge.symbol).font(.headline.weight(.regular))
                Spacer()
                Text(challenge.completed ? "Complete" : "+30 XP")
                    .font(.caption.weight(.semibold)).foregroundStyle(challenge.completed ? .green : STEWTheme.gold)
            }
            Text(challenge.title).font(.subheadline).foregroundStyle(.secondary)
            ProgressView(value: Double(challenge.progress), total: Double(challenge.target)).tint(challenge.completed ? .green : STEWTheme.gold)
            Text("\(min(challenge.progress, challenge.target)) of \(challenge.target)").font(.caption).foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .stewSurface()
        .accessibilityHint("Shows daily challenge details")
    }

    private var masteryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Skill mastery").font(.headline.weight(.regular))
                Spacer()
                Button("View All") { showingMastery = true }.font(.subheadline)
            }
            ForEach(EarTrainingMode.allCases) { item in
                let score = progress.averageMastery(for: item)
                HStack {
                    Text(item.rawValue).font(.subheadline)
                    Spacer()
                    Text(masteryTitle(score)).font(.caption).foregroundStyle(.secondary)
                }
                ProgressView(value: score, total: 100).tint(STEWTheme.gold)
                    .animation(reduceMotion ? nil : .smooth(duration: 0.5), value: score)
            }
        }
        .stewSurface()
    }

    private var listeningTipCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Listening tip").font(.headline.weight(.regular))
                Spacer()
                if loadingExplanation { ProgressView() }
            }
            TypewriterText(
                text: explanation.stewPlainText,
                animates: animatingExplanation && !reduceMotion,
                onComplete: { animatingExplanation = false }
            )
                .font(.body.weight(.light))
                .foregroundStyle(.secondary)
            Button("Learn Why") { Task { await explain() } }
                .disabled(answeredChoice == nil || loadingExplanation || animatingExplanation)
        }
        .stewSurface()
    }

    private var roundLabel: String {
        progress.today.goalRewardAwarded ? "BONUS PRACTICE" : "ROUND \(min(progress.profile.dailyGoal, progress.today.answered + 1)) OF \(progress.profile.dailyGoal)"
    }
    private var animatedLevelProgress: Double {
        let level = ListenerLevel.level(for: displayedXP)
        guard let next = level.next else { return 1 }
        return Double(displayedXP - level.minimumXP) / Double(next.minimumXP - level.minimumXP)
    }
    private var prompt: String {
        switch mode {
        case .interval: "Play two notes, then identify the interval."
        case .chord: "Play the chord, then identify its quality."
        case .note: "Play the note, then identify its name."
        }
    }

    private func loadQuestion(for mode: EarTrainingMode) {
        question = EarTrainingQuestionFactory.makeQuestion(for: mode, profile: progress.profile)
        answeredChoice = nil
        lastOutcome = nil
        nextQuestionVisible = false
        isPlayingQuestion = false
        animatingExplanation = false
        explanation = "Choose an answer to reveal a listening tip."
    }

    private func playQuestion() {
        guard let question, !isPlayingQuestion else { return }
        isPlayingQuestion = true
        for (index, midi) in question.midis.enumerated() {
            let delay = question.mode == .interval ? Double(index) * 0.65 : 0
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { player.play(midi: midi) }
        }
        let listeningDuration = question.mode == .interval ? 1.35 : 0.75
        DispatchQueue.main.asyncAfter(deadline: .now() + listeningDuration) {
            isPlayingQuestion = false
            UIAccessibility.post(notification: .announcement, argument: "Choose an answer")
        }
    }

    private func answer(_ choice: String) {
        guard answeredChoice == nil, let question else { return }
        let outcome = progress.answer(question, choice: choice)
        withAnimation(reduceMotion ? nil : .snappy) {
            answeredChoice = choice
            lastOutcome = outcome
        }
        sessionAnswered += 1
        sessionCorrect += outcome.correct ? 1 : 0
        sessionXP += outcome.xpEarned + (outcome.goalCompleted ? 25 : 0) + (outcome.challengeCompleted ? 30 : 0)
        sessionBestCombo = max(sessionBestCombo, outcome.combo)
        feedbackPulse += 1
        if !outcome.correct, !reduceMotion {
            withAnimation(.linear(duration: 0.34)) { shakeTrigger += 1 }
        }
        if outcome.xpEarned > 0 {
            floatingXP = outcome.xpEarned
            xpFloatVisible = false
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.65)) { xpFloatVisible = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.68) { floatingXP = nil }
        }
        if [2, 3, 5].contains(outcome.combo), !reduceMotion {
            withAnimation(.bouncy(duration: 0.25)) { comboPulse = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) { withAnimation(.easeOut(duration: 0.2)) { comboPulse = false } }
        }
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.55)) { displayedXP = outcome.currentTotalXP }
        if outcome.challengeCompleted {
            withAnimation(reduceMotion ? nil : .snappy) { challengeBannerVisible = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.25) {
                withAnimation(reduceMotion ? nil : .easeOut) { challengeBannerVisible = false }
            }
        }
        let feedbackDelay = voiceOverEnabled ? 0.1 : 0.38
        DispatchQueue.main.asyncAfter(deadline: .now() + feedbackDelay) {
            withAnimation(reduceMotion ? nil : .snappy) { nextQuestionVisible = true }
            eventQueue.enqueue(EarTrainingUXEvent.events(for: outcome))
            presentNextEventIfNeeded()
        }
    }

    private func completeActiveCelebration() {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { activeEvent = nil }
        DispatchQueue.main.asyncAfter(deadline: .now() + (reduceMotion ? 0 : 0.22)) { presentNextEventIfNeeded() }
    }

    private func resumeCelebrationQueue() {
        guard activeEvent != nil else { presentNextEventIfNeeded(); return }
    }

    private func presentNextEventIfNeeded() {
        guard activeEvent == nil, !showingAchievements else { return }
        guard let next = eventQueue.next() else { return }
        if next == .results {
            showingResults = true
        } else {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) { activeEvent = next }
            UIAccessibility.post(notification: .screenChanged, argument: eventAnnouncement(next))
        }
    }

    private func eventAnnouncement(_ event: EarTrainingUXEvent) -> String {
        switch event {
        case let .achievement(value): "Achievement unlocked. \(value.title). \(value.detail)"
        case let .levelUp(value): "Listener level up. \(value.rawValue)"
        case let .mastery(value): "\(value.skillLabel) improved from \(value.previousTitle) to \(value.currentTitle)"
        case .results: "Daily goal complete"
        }
    }

    private func answerColor(for choice: String) -> Color {
        guard let answeredChoice, let question else { return STEWTheme.ink }
        if choice == question.label { return .green }
        return choice == answeredChoice ? .orange : STEWTheme.ink
    }
    private func answerSymbol(for choice: String) -> String? {
        guard let answeredChoice, let question else { return nil }
        if choice == question.label { return "checkmark" }
        return choice == answeredChoice ? "xmark" : nil
    }
    private func answerAccessibilityLabel(for choice: String) -> String {
        guard let answeredChoice, let question else { return choice }
        if choice == question.label { return "\(choice), correct answer" }
        return choice == answeredChoice ? "\(choice), your incorrect answer" : choice
    }
    private func masteryTitle(_ score: Double) -> String {
        var mastery = SkillMastery(); mastery.score = score; return mastery.title
    }
    private func explain() async {
        guard let question else { return }
        loadingExplanation = true
        animatingExplanation = false
        defer { loadingExplanation = false }
        do {
            explanation = try await APIClient.shared.chat(message: "Explain how to recognize \(question.label) by ear.", mode: .earExplanation, history: []).0
            animatingExplanation = !reduceMotion
        } catch {
            explanation = error.localizedDescription
        }
    }
}

private struct EarTrainingSettingsView: View {
    @EnvironmentObject private var progress: EarTrainingProgressStore
    @Environment(\.dismiss) private var dismiss

    var reminderDate: Binding<Date> {
        Binding {
            Calendar.current.date(from: DateComponents(hour: progress.profile.reminderHour, minute: progress.profile.reminderMinute)) ?? Date()
        } set: { value in Task { await progress.setReminderTime(value) } }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Daily goal") {
                    Picker("Questions per day", selection: Binding(get: { progress.profile.dailyGoal }, set: { progress.setDailyGoal($0) })) {
                        ForEach([5, 10, 15], id: \.self) { Text("\($0) questions").tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Text("Answering a question advances your goal, even when you are still learning it.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Practice reminder") {
                    Toggle("Daily reminder", isOn: Binding(get: { progress.profile.remindersEnabled }, set: { enabled in Task { await progress.setReminder(enabled: enabled) } }))
                    if progress.profile.remindersEnabled {
                        DatePicker("Reminder time", selection: reminderDate, displayedComponents: .hourAndMinute)
                    }
                    if progress.notificationPermissionDenied {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Notifications are disabled for STEW.").foregroundStyle(.secondary)
                            Button("Open iOS Settings") {
                                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                            }
                        }
                    }
                }
            }
            .adaptiveFormWidth()
            .navigationTitle("Ear Training Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

private struct AchievementsView: View {
    @EnvironmentObject private var progress: EarTrainingProgressStore
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List(AchievementID.allCases) { achievement in
                let unlocked = progress.profile.unlockedAchievements.contains(achievement)
                HStack(spacing: 14) {
                    Image(systemName: achievement.symbol)
                        .font(.title2)
                        .foregroundStyle(unlocked ? STEWTheme.gold : Color.secondary)
                        .frame(width: 36)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack { Text(achievement.title).font(.headline.weight(.regular)); if unlocked { Image(systemName: "checkmark.seal.fill").foregroundStyle(.green) } }
                        Text(achievement.detail).font(.subheadline).foregroundStyle(.secondary)
                        if !unlocked { ProgressView(value: progress.achievementProgress(achievement)).tint(STEWTheme.gold) }
                    }
                }
                .padding(.vertical, 4)
                .accessibilityElement(children: .combine)
            }
            .navigationTitle("Achievements")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

private struct MasteryView: View {
    @EnvironmentObject private var progress: EarTrainingProgressStore
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                ForEach(EarTrainingMode.allCases) { mode in
                    Section(mode.rawValue) {
                        ForEach(EarTrainingQuestionFactory.skills(for: mode), id: \.id) { skill in
                            let mastery = progress.mastery(for: skill.id)
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(skill.label)
                                    Spacer()
                                    Text(mastery.title).font(.caption).foregroundStyle(.secondary)
                                }
                                ProgressView(value: mastery.score, total: 100).tint(STEWTheme.gold)
                                Text("\(mastery.correct) of \(mastery.attempts) correct")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 3)
                        }
                    }
                }
            }
            .navigationTitle("Skill Mastery")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

private struct SessionResultsView: View {
    let answered: Int
    let correct: Int
    let xp: Int
    let bestCombo: Int
    let challengeCompleted: Bool
    let achievements: [AchievementID]
    let continueAction: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    Image(systemName: "checkmark.seal.fill").font(.system(size: 54)).foregroundStyle(STEWTheme.gold)
                    VStack(spacing: 6) {
                        Text("Daily goal complete").font(.title.weight(.light))
                        Text("Your ears are a little sharper than yesterday.").foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                    HStack(spacing: 0) {
                        resultStat("Accuracy", answered == 0 ? "0%" : "\(Int((Double(correct) / Double(answered)) * 100))%")
                        Rectangle().fill(Color(.separator)).frame(width: 1, height: 44)
                        resultStat("XP earned", "+\(xp)")
                        Rectangle().fill(Color(.separator)).frame(width: 1, height: 44)
                        resultStat("Best combo", "×\(bestCombo)")
                    }
                    .stewSurface()
                    if challengeCompleted { Label("Daily challenge complete", systemImage: "star.fill").foregroundStyle(STEWTheme.gold) }
                    ForEach(achievements) { item in Label("Achievement unlocked: \(item.title)", systemImage: item.symbol).foregroundStyle(STEWTheme.gold) }
                    Button("Keep Practicing", action: continueAction)
                        .buttonStyle(.borderedProminent).tint(STEWTheme.ink)
                        .frame(maxWidth: .infinity)
                }
                .padding(24)
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
        .interactiveDismissDisabled()
    }

    private func resultStat(_ label: String, _ value: String) -> some View {
        VStack(spacing: 3) { Text(value).font(.headline.monospacedDigit()); Text(label).font(.caption).foregroundStyle(.secondary) }
            .frame(maxWidth: .infinity)
    }
}
