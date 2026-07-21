import SwiftUI

struct AchievementPopupView: View {
    let achievement: AchievementID
    let reduceMotion: Bool
    let continueAction: () -> Void
    let viewAchievements: () -> Void
    @State private var drawSymbol = false
    @State private var revealCopy = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.34).ignoresSafeArea()
            VStack(spacing: 20) {
                ZStack {
                    GoldSparkles(active: drawSymbol && !reduceMotion)
                    if drawSymbol {
                        if reduceMotion {
                            achievementSymbol.transition(.opacity)
                        } else {
                            achievementSymbol.transition(.symbolEffect(.drawOn.byLayer, options: .speed(1.15)))
                        }
                    }
                }
                VStack(spacing: 7) {
                    Text("ACHIEVEMENT UNLOCKED")
                        .font(.caption.weight(.semibold)).tracking(1.4).foregroundStyle(STEWTheme.gold)
                    Text(achievement.title).font(.title2.weight(.light))
                    Text(achievement.detail).font(.body.weight(.light)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Text("Milestone added to your collection")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .opacity(revealCopy ? 1 : 0)
                VStack(spacing: 10) {
                    Button("Continue", action: continueAction)
                        .buttonStyle(.borderedProminent).tint(STEWTheme.ink)
                        .frame(maxWidth: .infinity)
                    Button("View Achievements", action: viewAchievements)
                }
                .opacity(revealCopy ? 1 : 0)
            }
            .padding(26)
            .frame(maxWidth: 340)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 28))
            .overlay { RoundedRectangle(cornerRadius: 28).stroke(STEWTheme.gold.opacity(0.65), lineWidth: 1) }
            .shadow(color: STEWTheme.gold.opacity(0.22), radius: 24)
            .padding()
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isModal)
            .accessibilityIdentifier("achievement-popup")
        }
        .transition(.opacity)
        .onAppear {
            if reduceMotion {
                drawSymbol = true
                revealCopy = true
            } else {
                withAnimation { drawSymbol = true }
                withAnimation(.easeOut(duration: 0.3).delay(0.72)) { revealCopy = true }
            }
        }
    }

    private var achievementSymbol: some View {
        Image(systemName: achievement.symbol)
            .font(.system(size: 58, weight: .light))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(STEWTheme.gold)
            .frame(width: 104, height: 88)
    }
}

struct MilestonePopupView: View {
    let event: EarTrainingUXEvent
    let continueAction: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var visible = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.28).ignoresSafeArea()
            VStack(spacing: 16) {
                if visible {
                    if reduceMotion {
                        milestoneSymbol.transition(.opacity)
                    } else {
                        milestoneSymbol.transition(.symbolEffect(.drawOn.byLayer, options: .speed(1.25)))
                    }
                }
                Text(kicker).font(.caption.weight(.semibold)).tracking(1.3).foregroundStyle(STEWTheme.gold)
                Text(title).font(.title2.weight(.light)).multilineTextAlignment(.center)
                Text(detail).font(.body.weight(.light)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Button("Continue", action: continueAction).buttonStyle(.borderedProminent).tint(STEWTheme.ink)
            }
            .padding(26)
            .frame(maxWidth: 330)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 26))
            .overlay { RoundedRectangle(cornerRadius: 26).stroke(STEWTheme.gold.opacity(0.5), lineWidth: 1) }
            .padding()
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isModal)
            .accessibilityIdentifier("milestone-popup")
        }
        .onAppear { withAnimation { visible = true } }
    }

    private var kicker: String {
        if case .levelUp = event { return "LISTENER LEVEL UP" }
        return "SKILL IMPROVED"
    }
    private var symbol: String {
        if case .levelUp = event { return "waveform.badge.plus" }
        return "chart.line.uptrend.xyaxis"
    }
    private var title: String {
        switch event {
        case let .levelUp(level): "Level \(level.number) · \(level.rawValue)"
        case let .mastery(change): change.skillLabel
        default: "Progress updated"
        }
    }
    private var detail: String {
        switch event {
        case let .levelUp(level): "Your listening practice has reached the \(level.rawValue) level."
        case let .mastery(change): "\(change.previousTitle) → \(change.currentTitle)"
        default: "Keep listening."
        }
    }
    private var milestoneSymbol: some View {
        Image(systemName: symbol)
            .font(.system(size: 48, weight: .light))
            .foregroundStyle(STEWTheme.gold)
    }
}

struct GoldSparkles: View {
    let active: Bool
    var body: some View {
        ZStack {
            ForEach(0..<6, id: \.self) { index in
                Image(systemName: index.isMultiple(of: 2) ? "sparkle" : "diamond.fill")
                    .font(.system(size: index.isMultiple(of: 2) ? 12 : 6))
                    .foregroundStyle(STEWTheme.gold.opacity(0.75))
                    .offset(x: cos(Double(index) * .pi / 3) * 52, y: sin(Double(index) * .pi / 3) * 40)
                    .scaleEffect(active ? 1 : 0.2)
                    .opacity(active ? 1 : 0)
                    .animation(.easeOut(duration: 0.45).delay(0.72 + Double(index) * 0.04), value: active)
            }
        }
        .frame(width: 130, height: 100)
        .accessibilityHidden(true)
    }
}

struct StreakDetailView: View {
    @EnvironmentObject private var progress: EarTrainingProgressStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 18) {
                        stat("Current", "\(progress.profile.currentStreak) days")
                        stat("Longest", "\(progress.profile.longestStreak) days")
                    }
                    .stewSurface()
                    VStack(alignment: .leading, spacing: 12) {
                        Text("This week").font(.headline.weight(.regular))
                        HStack {
                            ForEach(Array(progress.weekDayKeys().enumerated()), id: \.element) { index, key in
                                VStack(spacing: 7) {
                                    Text(Calendar.current.shortWeekdaySymbols[index]).font(.caption2).foregroundStyle(.secondary)
                                    Image(systemName: progress.profile.completedGoalDays.contains(key) ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(progress.profile.completedGoalDays.contains(key) ? STEWTheme.gold : Color.secondary)
                                }
                                .frame(maxWidth: .infinity)
                            }
                        }
                    }
                    .stewSurface()
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Next milestone").font(.headline.weight(.regular))
                        Text("\(nextMilestone) day streak").font(.title2.weight(.light))
                        ProgressView(value: min(1, Double(progress.profile.currentStreak) / Double(nextMilestone))).tint(STEWTheme.gold)
                    }
                    .stewSurface()
                    Label("Missing a calendar day resets the current streak. Your longest streak remains saved.", systemImage: "info.circle")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .padding()
            }
            .navigationTitle("Listening Streak")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    private var nextMilestone: Int { [3, 7, 14, 30, 60, 100].first(where: { $0 > progress.profile.currentStreak }) ?? 100 }
    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) { Text(value).font(.title2.weight(.light)); Text(label).font(.caption).foregroundStyle(.secondary) }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ChallengeDetailView: View {
    @EnvironmentObject private var progress: EarTrainingProgressStore
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: progress.today.challenge.symbol).font(.system(size: 48, weight: .light)).foregroundStyle(STEWTheme.gold)
                Text(progress.today.challenge.title).font(.title2.weight(.light)).multilineTextAlignment(.center)
                Text(progress.today.challenge.completed ? "Challenge complete" : "Complete this objective before the local day ends.")
                    .foregroundStyle(.secondary).multilineTextAlignment(.center)
                ProgressView(value: Double(progress.today.challenge.progress), total: Double(progress.today.challenge.target)).tint(STEWTheme.gold)
                Text("\(min(progress.today.challenge.progress, progress.today.challenge.target)) of \(progress.today.challenge.target)").font(.headline.monospacedDigit())
                Label("Reward: 30 XP", systemImage: "star.fill").foregroundStyle(STEWTheme.gold)
                Spacer()
            }
            .padding(28)
            .navigationTitle("Daily Challenge")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium])
    }
}

struct PressableAnswerButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct ShakeEffect: GeometryEffect {
    var amount: CGFloat = 7
    var shakes = 3
    var animatableData: CGFloat
    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: amount * sin(animatableData * .pi * CGFloat(shakes)), y: 0))
    }
}
