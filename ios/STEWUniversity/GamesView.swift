import SwiftUI

struct GamesView: View {
    @EnvironmentObject private var progress: GameProgressStore
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("MUSIC GAMES")
                        .font(.caption.weight(.medium))
                        .tracking(1.5)
                        .foregroundStyle(.secondary)
                    Text("Play with what you know").font(.title.weight(.light))
                    Text("Puzzle through harmony, memory, and sound—one focused game at a time.")
                        .font(.body.weight(.light))
                        .foregroundStyle(.secondary)
                }

                LazyVGrid(columns: gameColumns, spacing: 18) {
                    NavigationLink {
                        HarmonicSudokuView()
                    } label: {
                        gameCard(
                            title: "Harmonic Sudoku",
                            subtitle: "Place nine chords across a classic theory grid.",
                            symbol: "square.grid.3x3.fill",
                            accent: progress.isDailyComplete() ? "Daily complete" : "Daily puzzle ready",
                            stats: [
                                ("Streak", "\(progress.sudoku.currentDailyStreak) days"),
                                ("Solved", "\(progress.sudoku.solvedCount)"),
                                ("Best", bestSudokuTime)
                            ]
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("harmonic-sudoku-card")

                    NavigationLink {
                        MelodyMemoryView()
                    } label: {
                        gameCard(
                            title: "Melody Memory",
                            subtitle: "Listen closely, then play the growing melody back.",
                            symbol: "waveform.path.ecg",
                            accent: "Three hearts · endless play",
                            stats: [
                                ("High score", "\(progress.melody.highScore)"),
                                ("Longest", "\(progress.melody.longestSequence) notes"),
                                ("Played", "\(progress.melody.gamesPlayed)")
                            ]
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("melody-memory-card")
                }
            }
            .padding(18)
            .adaptiveContentWidth()
        }
        .background(Color(.systemBackground))
        .accessibilityIdentifier("games-hub")
    }

    private var gameColumns: [GridItem] {
        if horizontalSizeClass == .regular && !dynamicTypeSize.isAccessibilitySize {
            return [GridItem(.flexible()), GridItem(.flexible())]
        }
        return [GridItem(.flexible())]
    }

    private var bestSudokuTime: String {
        guard let value = progress.sudoku.bestUnassistedSeconds.values.min() else { return "—" }
        return GameFormatting.duration(value)
    }

    private func gameCard(
        title: String,
        subtitle: String,
        symbol: String,
        accent: String,
        stats: [(String, String)]
    ) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: symbol)
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(STEWTheme.gold)
                    .frame(width: 52, height: 52)
                    .background(STEWTheme.gold.opacity(0.13), in: RoundedRectangle(cornerRadius: 15))
                VStack(alignment: .leading, spacing: 5) {
                    Text(title).font(.title3.weight(.regular)).foregroundStyle(.primary)
                    Text(subtitle).font(.subheadline.weight(.light)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 2)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }
            Text(accent)
                .font(.caption.weight(.medium))
                .foregroundStyle(STEWTheme.gold)
            HStack(spacing: 0) {
                ForEach(Array(stats.enumerated()), id: \.offset) { index, stat in
                    VStack(spacing: 3) {
                        Text(stat.1).font(.subheadline.monospacedDigit()).foregroundStyle(.primary)
                        Text(stat.0).font(.caption2).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    if index < stats.count - 1 {
                        Rectangle().fill(Color(.separator)).frame(width: 0.5, height: 32)
                    }
                }
            }
        }
        .stewSurface()
        .contentShape(Rectangle())
    }
}
