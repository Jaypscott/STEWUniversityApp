import SwiftUI
import UIKit

struct MelodyMemoryView: View {
    private enum Phase: Equatable {
        case ready, playing, input, feedback, paused, gameOver
    }

    @EnvironmentObject private var progress: GameProgressStore
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var difficulty: MelodyDifficulty = .easy
    @State private var session: MelodyMemorySession?
    @State private var phase: Phase = .ready
    @State private var highlightedMIDI: Int?
    @State private var floatingPoints: Int?
    @State private var showingResults = false
    @State private var isNewRecord = false
    @State private var feedbackSignal = 0
    @State private var feedbackCorrect = true
    @State private var playbackTask: Task<Void, Never>?
    @StateObject private var player = PianoSamplePlayer()
    private let generator = RandomMelodyNoteGenerator()

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                header
                difficultyPicker
                if let session {
                    if horizontalSizeClass == .regular && !dynamicTypeSize.isAccessibilitySize {
                        HStack(alignment: .top, spacing: 20) {
                            VStack(spacing: 16) {
                                scoreCard(session)
                                instructionCard(session)
                                controls(session)
                            }
                            .frame(maxWidth: 380)

                            piano(session, height: 260)
                                .frame(maxWidth: .infinity)
                        }
                    } else {
                        scoreCard(session)
                        instructionCard(session)
                        piano(session, height: 184)
                        controls(session)
                    }
                } else {
                    readyCard
                }
            }
            .padding(18)
            .adaptiveContentWidth()
        }
        .background(Color(.systemBackground))
        .navigationTitle("Melody Memory")
        .navigationBarTitleDisplayMode(.inline)
        .overlay { if phase == .paused { pausedOverlay } }
        .onDisappear { playbackTask?.cancel() }
        .onChange(of: scenePhase) { _, newPhase in
            guard session != nil, phase != .ready, phase != .gameOver else { return }
            if newPhase != .active {
                playbackTask?.cancel()
                highlightedMIDI = nil
                phase = .paused
            }
        }
        .sheet(isPresented: $showingResults) {
            if let session {
                MelodyResultsView(session: session, isNewRecord: isNewRecord) {
                    showingResults = false
                    startGame()
                }
            }
        }
        .sensoryFeedback(feedbackCorrect ? .success : .error, trigger: feedbackSignal)
        .accessibilityIdentifier("melody-memory-screen")
    }

    private func piano(_ value: MelodyMemorySession, height: CGFloat) -> some View {
        MelodyPianoView(
            activeNotes: Set(value.difficulty.notePool),
            highlightedMIDI: highlightedMIDI,
            inputEnabled: phase == .input,
            height: height
        ) { submit($0) }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("LISTEN · REMEMBER · PLAY").font(.caption.weight(.medium)).tracking(1.5).foregroundStyle(.secondary)
            Text("How long can you hold the melody?").font(.title.weight(.light))
            Text("Each round adds another piano note. Three missed notes end the run.")
                .font(.body.weight(.light)).foregroundStyle(.secondary)
        }
    }

    private var difficultyPicker: some View {
        Picker("Difficulty", selection: $difficulty) {
            ForEach(MelodyDifficulty.allCases) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
        .disabled(session != nil && phase != .gameOver)
    }

    private var readyCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "ear.and.waveform").font(.system(size: 34, weight: .light)).foregroundStyle(STEWTheme.gold)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Best · \(difficulty.rawValue)").font(.caption).foregroundStyle(.secondary)
                    Text("\(progress.melody.bestScores[difficulty.rawValue] ?? 0) points").font(.headline.monospacedDigit())
                }
            }
            Text(difficultyDescription).font(.subheadline).foregroundStyle(.secondary)
            Button { startGame() } label: {
                Label("Start Listening", systemImage: "play.fill").frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent).tint(STEWTheme.ink)
            .accessibilityIdentifier("start-melody-memory")
        }
        .stewSurface()
    }

    private var difficultyDescription: String {
        switch difficulty {
        case .easy: "Five C-major pentatonic notes with relaxed playback."
        case .medium: "The full C-major octave at a quicker pace."
        case .hard: "All chromatic notes from C4 through C5."
        }
    }

    private func scoreCard(_ value: MelodyMemorySession) -> some View {
        HStack(spacing: 0) {
            melodyStat("Score", "\(value.score)")
            Divider().frame(height: 38)
            melodyStat("Length", "\(value.sequence.count)")
            Divider().frame(height: 38)
            VStack(spacing: 4) {
                HStack(spacing: 4) {
                    ForEach(0..<3, id: \.self) { index in
                        Image(systemName: index < value.hearts ? "heart.fill" : "heart")
                            .font(.caption).foregroundStyle(index < value.hearts ? Color.red : Color.secondary)
                    }
                }
                Text("Hearts").font(.caption2).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
        .stewSurface()
    }

    private func melodyStat(_ title: String, _ value: String) -> some View {
        VStack(spacing: 3) {
            Text(value).font(.headline.monospacedDigit())
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func instructionCard(_ value: MelodyMemorySession) -> some View {
        VStack(spacing: 10) {
            ZStack {
                Text(phaseTitle).font(.headline.weight(.regular))
                if let floatingPoints {
                    Text("+\(floatingPoints)")
                        .font(.headline.monospacedDigit()).foregroundStyle(STEWTheme.gold)
                        .offset(y: reduceMotion ? -28 : -42)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            ProgressView(value: Double(value.inputIndex), total: Double(max(1, value.sequence.count)))
                .tint(STEWTheme.gold)
            Text("\(value.inputIndex) of \(value.sequence.count) notes")
                .font(.caption).foregroundStyle(.secondary).monospacedDigit()
        }
        .frame(maxWidth: .infinity)
        .stewSurface()
        .accessibilityElement(children: .combine)
    }

    private var phaseTitle: String {
        switch phase {
        case .ready: "Get ready"
        case .playing: "Listen closely…"
        case .input: "Now play it back"
        case .feedback: "Hold that melody"
        case .paused: "Game paused"
        case .gameOver: "Run complete"
        }
    }

    private func controls(_ value: MelodyMemorySession) -> some View {
        HStack(spacing: 12) {
            Button { replay() } label: {
                Label(value.replayUsedThisRound ? "Replay Used" : "Replay Once", systemImage: "gobackward")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .disabled(phase != .input || value.replayUsedThisRound)
            Button { endRun() } label: {
                Text("End Run").frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .disabled(phase == .playing || phase == .feedback)
        }
    }

    private var pausedOverlay: some View {
        ZStack {
            Color.black.opacity(0.3).ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "pause.circle").font(.system(size: 48, weight: .light)).foregroundStyle(STEWTheme.gold)
                Text("Melody paused").font(.title2.weight(.light))
                Text("Continue when you are ready to hear the sequence again.")
                    .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Button("Continue") { playSequence() }.buttonStyle(.borderedProminent).tint(STEWTheme.ink)
            }
            .padding(26).frame(maxWidth: 320)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 24))
            .padding()
        }
        .accessibilityAddTraits(.isModal)
    }

    private func startGame() {
        playbackTask?.cancel()
        let newSession = MelodyMemorySession(difficulty: difficulty, generator: generator)
        session = newSession
        phase = .ready
        highlightedMIDI = nil
        floatingPoints = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { playSequence() }
    }

    private func playSequence() {
        guard let notes = session?.sequence, let spacing = session?.difficulty.noteSpacing else { return }
        playbackTask?.cancel()
        phase = .playing
        highlightedMIDI = nil
        playbackTask = Task { @MainActor in
            for midi in notes {
                guard !Task.isCancelled else { return }
                highlightedMIDI = midi
                player.play(midi: midi)
                try? await Task.sleep(nanoseconds: UInt64(spacing * 1_000_000_000))
                highlightedMIDI = nil
                try? await Task.sleep(nanoseconds: 80_000_000)
            }
            guard !Task.isCancelled else { return }
            phase = .input
            UIAccessibility.post(notification: .announcement, argument: "Now play the melody back")
        }
    }

    private func submit(_ midi: Int) {
        guard phase == .input, var value = session else { return }
        player.play(midi: midi)
        highlightedMIDI = midi
        let outcome = value.submit(midi)
        session = value
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { if highlightedMIDI == midi { highlightedMIDI = nil } }
        switch outcome {
        case .correctNote:
            feedbackCorrect = true; feedbackSignal += 1
        case let .roundComplete(points):
            feedbackCorrect = true; feedbackSignal += 1
            phase = .feedback
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) { floatingPoints = points }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.72) {
                guard var current = session else { return }
                current.advance(using: generator)
                session = current
                floatingPoints = nil
                playSequence()
            }
        case .retry:
            feedbackCorrect = false; feedbackSignal += 1
            phase = .feedback
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.72) { playSequence() }
        case .gameOver:
            feedbackCorrect = false; feedbackSignal += 1
            finishRun(value)
        }
    }

    private func replay() {
        guard var value = session, value.useReplay() else { return }
        session = value
        playSequence()
    }

    private func endRun() {
        guard let session else { return }
        finishRun(session)
    }

    private func finishRun(_ value: MelodyMemorySession) {
        playbackTask?.cancel()
        phase = .gameOver
        highlightedMIDI = nil
        isNewRecord = value.score > progress.melody.highScore
        progress.recordMelodyResult(value)
        session = value
        showingResults = true
    }
}

private struct MelodyPianoView: View {
    let activeNotes: Set<Int>
    let highlightedMIDI: Int?
    let inputEnabled: Bool
    let height: CGFloat
    let play: (Int) -> Void

    private let whites = [60, 62, 64, 65, 67, 69, 71, 72]
    private let blacks = [(61, 0), (63, 1), (66, 3), (68, 4), (70, 5)]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(inputEnabled ? "Tap the piano in order" : "Piano input is locked while listening")
                .font(.caption).foregroundStyle(.secondary)
            GeometryReader { geometry in
                let whiteWidth = geometry.size.width / CGFloat(whites.count)
                ZStack(alignment: .topLeading) {
                    ForEach(Array(whites.enumerated()), id: \.element) { index, midi in
                        key(midi: midi, black: false)
                            .frame(width: whiteWidth - 1, height: height)
                            .position(x: CGFloat(index) * whiteWidth + whiteWidth / 2, y: height / 2)
                    }
                    ForEach(blacks, id: \.0) { midi, boundary in
                        key(midi: midi, black: true)
                            .frame(width: whiteWidth * 0.58, height: height * 0.59)
                            .position(x: CGFloat(boundary + 1) * whiteWidth, y: height * 0.295)
                            .zIndex(2)
                    }
                }
            }
            .frame(height: height)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Melody piano")
    }

    private func key(midi: Int, black: Bool) -> some View {
        let active = activeNotes.contains(midi)
        let highlighted = highlightedMIDI == midi
        return Button { play(midi) } label: {
            VStack {
                Spacer()
                if !black {
                    Text(noteName(midi)).font(.caption2).foregroundStyle(active ? Color.secondary : Color.secondary.opacity(0.35)).padding(.bottom, 8)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(keyColor(black: black, active: active, highlighted: highlighted))
            .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 5, bottomTrailingRadius: 5))
            .overlay {
                UnevenRoundedRectangle(bottomLeadingRadius: 5, bottomTrailingRadius: 5)
                    .stroke(highlighted ? STEWTheme.gold : Color.black.opacity(black ? 0.65 : 0.22), lineWidth: highlighted ? 3 : 0.7)
            }
            .shadow(color: .black.opacity(black ? 0.3 : 0.1), radius: black ? 3 : 1, y: black ? 3 : 1)
        }
        .buttonStyle(MelodyPianoKeyStyle())
        .disabled(!inputEnabled || !active)
        .accessibilityLabel("Play \(noteName(midi))")
    }

    private func keyColor(black: Bool, active: Bool, highlighted: Bool) -> Color {
        if highlighted { return STEWTheme.gold }
        if !active { return black ? Color.black.opacity(0.45) : Color.gray.opacity(0.25) }
        return black ? Color(red: 0.055, green: 0.06, blue: 0.07) : .white
    }

    private func noteName(_ midi: Int) -> String {
        let names = ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"]
        return names[midi % 12] + "\(midi / 12 - 1)"
    }
}

private struct MelodyPianoKeyStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(x: 1, y: configuration.isPressed ? 0.975 : 1, anchor: .top)
            .brightness(configuration.isPressed ? -0.08 : 0)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

private struct MelodyResultsView: View {
    @Environment(\.dismiss) private var dismiss
    let session: MelodyMemorySession
    let isNewRecord: Bool
    let playAgain: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 22) {
                Image(systemName: isNewRecord ? "trophy.fill" : "waveform.path.ecg")
                    .font(.system(size: 52, weight: .light)).foregroundStyle(STEWTheme.gold)
                VStack(spacing: 6) {
                    Text(isNewRecord ? "New high score" : "Melody complete").font(.title.weight(.light))
                    Text(session.difficulty.rawValue).foregroundStyle(.secondary)
                }
                HStack(spacing: 0) {
                    resultStat("Score", "\(session.score)")
                    Divider().frame(height: 42)
                    resultStat("Longest", "\(session.sequence.count)")
                    Divider().frame(height: 42)
                    resultStat("Rounds", "\(session.completedRounds)")
                }
                .stewSurface()
                Button("Play Again") { dismiss(); playAgain() }
                    .buttonStyle(.borderedProminent).tint(STEWTheme.ink)
                    .frame(maxWidth: .infinity)
            }
            .padding(24)
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
        .interactiveDismissDisabled()
        .accessibilityIdentifier("melody-results")
    }

    private func resultStat(_ label: String, _ value: String) -> some View {
        VStack(spacing: 3) {
            Text(value).font(.headline.monospacedDigit())
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
