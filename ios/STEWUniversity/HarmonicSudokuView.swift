import SwiftUI
import UIKit

struct HarmonicSudokuView: View {
    @EnvironmentObject private var progress: GameProgressStore
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var mode: SudokuMode = .daily
    @State private var practiceDifficulty: SudokuDifficulty = .easy
    @State private var session: SudokuSession?
    @State private var selectedIndex: Int?
    @State private var notesMode = false
    @State private var showingTheory = false
    @State private var showingResults = false
    @State private var feedbackSignal = 0
    @State private var feedbackCorrect = true
    @StateObject private var player = PianoSamplePlayer()

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                header
                Picker("Puzzle type", selection: $mode) {
                    ForEach(SudokuMode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                if mode == .practice { practiceControls }

                if let session {
                    statusCard(session)
                    if horizontalSizeClass == .regular && !dynamicTypeSize.isAccessibilitySize {
                        HStack(alignment: .top, spacing: 20) {
                            SudokuBoardView(session: session, selectedIndex: $selectedIndex)
                                .frame(maxWidth: 620)

                            VStack(spacing: 14) {
                                actionBar(session)
                                chordPalette(session)
                                selectedRowCard(session)
                            }
                            .frame(maxWidth: 430)
                        }
                    } else {
                        SudokuBoardView(session: session, selectedIndex: $selectedIndex)
                        actionBar(session)
                        chordPalette(session)
                        selectedRowCard(session)
                    }
                } else {
                    ProgressView("Preparing puzzle…").frame(maxWidth: .infinity, minHeight: 220)
                }
            }
            .padding(18)
            .adaptiveContentWidth()
        }
        .background(Color(.systemBackground))
        .navigationTitle("Harmonic Sudoku")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingTheory = true } label: { Image(systemName: "info.circle") }
                    .accessibilityLabel("How Harmonic Sudoku works")
            }
        }
        .onAppear { loadSession() }
        .onDisappear { pauseAndSave() }
        .onChange(of: mode) { _, _ in switchMode() }
        .onChange(of: practiceDifficulty) { _, _ in loadSession() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { pauseAndSave() }
        }
        .sheet(isPresented: $showingTheory) { HarmonicSudokuTheoryView(palette: session?.puzzle.palette) }
        .sheet(isPresented: $showingResults) {
            if let session {
                SudokuResultsView(session: session) {
                    showingResults = false
                    if mode == .practice { startNewPractice() }
                }
            }
        }
        .sensoryFeedback(feedbackCorrect ? .success : .error, trigger: feedbackSignal)
        .accessibilityIdentifier("harmonic-sudoku-screen")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("HARMONY PUZZLE").font(.caption.weight(.medium)).tracking(1.5).foregroundStyle(.secondary)
            Text("Every chord has its place").font(.title.weight(.light))
            Text("Fill each row, column, and region with all nine harmonic functions.")
                .font(.body.weight(.light)).foregroundStyle(.secondary)
        }
    }

    private var practiceControls: some View {
        HStack(spacing: 12) {
            Picker("Difficulty", selection: $practiceDifficulty) {
                ForEach(SudokuDifficulty.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .padding(.horizontal, 12)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))

            Button { startNewPractice() } label: {
                Label("New", systemImage: "arrow.clockwise").frame(minHeight: 44)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("New \(practiceDifficulty.rawValue) practice puzzle")
        }
    }

    private func statusCard(_ value: SudokuSession) -> some View {
        let palette = value.puzzle.palette
        return HStack(spacing: 0) {
            statusItem("Key", palette.keyName)
            Divider().frame(height: 34)
            TimelineView(.periodic(from: .now, by: 1)) { context in
                statusItem("Time", GameFormatting.duration(value.elapsed(at: context.date)))
            }
            Divider().frame(height: 34)
            statusItem("Mistakes", "\(value.mistakes)")
            Divider().frame(height: 34)
            statusItem("Hints", "\(value.hintsUsed)/3")
        }
        .stewSurface()
    }

    private func statusItem(_ title: String, _ value: String) -> some View {
        VStack(spacing: 3) {
            Text(value).font(.subheadline.monospacedDigit()).lineLimit(1).minimumScaleFactor(0.7)
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func actionBar(_ value: SudokuSession) -> some View {
        HStack(spacing: 8) {
            puzzleAction("Notes", systemImage: notesMode ? "pencil.circle.fill" : "pencil.circle", selected: notesMode) {
                notesMode.toggle()
            }
            puzzleAction("Erase", systemImage: "eraser") { eraseSelected() }
                .disabled(!canEditSelected(value))
            puzzleAction("Undo", systemImage: "arrow.uturn.backward") { undo() }
                .disabled(value.undoHistory.isEmpty || value.completed)
            puzzleAction("Hint", systemImage: "lightbulb") { useHint() }
                .disabled(value.hintsUsed >= 3 || value.completed)
        }
    }

    private func puzzleAction(
        _ title: String,
        systemImage: String,
        selected: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemImage).font(.body)
                Text(title).font(.caption2)
            }
            .frame(maxWidth: .infinity, minHeight: 48)
            .foregroundStyle(selected ? STEWTheme.ink : .primary)
            .background(selected ? STEWTheme.gold : Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private func chordPalette(_ value: SudokuSession) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
            ForEach(value.puzzle.palette.chords) { chord in
                Button { enter(chord.token.rawValue) } label: {
                    HStack(spacing: 7) {
                        Text(chord.roman).font(.subheadline.weight(.semibold))
                        Text(chord.name).font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12).stroke(Color(.separator).opacity(0.45), lineWidth: 0.5)
                    }
                }
                .buttonStyle(.plain)
                .disabled(!canEditSelected(value))
                .accessibilityLabel("Enter \(chord.roman), \(chord.name)")
                .accessibilityIdentifier("sudoku-value-\(chord.token.rawValue)")
            }
        }
    }

    @ViewBuilder
    private func selectedRowCard(_ value: SudokuSession) -> some View {
        if let selectedIndex {
            let row = selectedIndex / 9
            let rowValues = Array(value.entries[(row * 9)..<(row * 9 + 9)])
            let rowComplete = rowValues.enumerated().allSatisfy { offset, entry in
                entry == value.puzzle.solution[row * 9 + offset]
            }
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Selected row").font(.headline.weight(.regular))
                    Text(rowComplete ? "The progression is ready to hear." : "Complete this row to hear the progression.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button { playRow(row, session: value) } label: { Label("Play Row", systemImage: "play.fill") }
                    .buttonStyle(.bordered)
                    .disabled(!rowComplete)
            }
            .stewSurface()
        }
    }

    private func canEditSelected(_ value: SudokuSession) -> Bool {
        guard let selectedIndex, !value.completed else { return false }
        return value.puzzle.givens[selectedIndex] == nil
    }

    private func loadSession() {
        pauseAndSave()
        session = mode == .daily
            ? progress.dailySession()
            : progress.practiceSession(difficulty: practiceDifficulty)
        selectedIndex = firstEditableIndex(in: session)
        notesMode = false
        if ProcessInfo.processInfo.arguments.contains("--ui-testing-sudoku-near-complete"), var value = session {
            value.entries = value.puzzle.solution.map(Optional.some)
            if let index = value.puzzle.givens.indices.first(where: {
                value.puzzle.givens[$0] == nil && value.puzzle.solution[$0] == HarmonicChordToken.tonic.rawValue
            }) {
                value.entries[index] = nil
                selectedIndex = index
            }
            session = value
            progress.saveSudoku(value)
        }
    }

    private func switchMode() {
        pauseAndSave()
        selectedIndex = nil
        loadSession()
    }

    private func startNewPractice() {
        pauseAndSave()
        session = progress.newPracticeSession(difficulty: practiceDifficulty)
        selectedIndex = firstEditableIndex(in: session)
        notesMode = false
    }

    private func firstEditableIndex(in session: SudokuSession?) -> Int? {
        session?.puzzle.givens.indices.first { session?.puzzle.givens[$0] == nil }
    }

    private func enter(_ value: Int) {
        guard let selectedIndex, var session, canEditSelected(session) else { return }
        session.begin(at: Date())
        session.pushUndo()
        if notesMode, session.entries[selectedIndex] == nil {
            if session.candidates[selectedIndex].contains(value) { session.candidates[selectedIndex].remove(value) }
            else { session.candidates[selectedIndex].insert(value) }
            self.session = session
            progress.saveSudoku(session)
            return
        }
        session.entries[selectedIndex] = value
        session.candidates[selectedIndex].removeAll()
        let correct = value == session.puzzle.solution[selectedIndex]
        if correct {
            removeCandidate(value, around: selectedIndex, in: &session)
            playChord(value, palette: session.puzzle.palette)
        } else {
            session.mistakes += 1
        }
        feedbackCorrect = correct
        feedbackSignal += 1
        self.session = session
        progress.saveSudoku(session)
        finishIfNeeded()
    }

    private func eraseSelected() {
        guard let selectedIndex, var session, canEditSelected(session) else { return }
        session.begin(at: Date())
        session.pushUndo()
        session.entries[selectedIndex] = nil
        session.candidates[selectedIndex].removeAll()
        session.hintedIndices.remove(selectedIndex)
        self.session = session
        progress.saveSudoku(session)
    }

    private func undo() {
        guard var session, !session.completed else { return }
        session.undo()
        self.session = session
        progress.saveSudoku(session)
    }

    private func useHint() {
        guard var session, session.hintsUsed < 3, !session.completed else { return }
        let index: Int?
        if let selectedIndex, session.entries[selectedIndex] != session.puzzle.solution[selectedIndex], session.puzzle.givens[selectedIndex] == nil {
            index = selectedIndex
        } else {
            index = session.entries.indices.first {
                session.puzzle.givens[$0] == nil && session.entries[$0] != session.puzzle.solution[$0]
            }
        }
        guard let index else { return }
        session.begin(at: Date())
        session.pushUndo()
        let value = session.puzzle.solution[index]
        session.entries[index] = value
        session.candidates[index].removeAll()
        session.hintedIndices.insert(index)
        session.hintsUsed += 1
        removeCandidate(value, around: index, in: &session)
        selectedIndex = index
        self.session = session
        progress.saveSudoku(session)
        playChord(value, palette: session.puzzle.palette)
        feedbackCorrect = true
        feedbackSignal += 1
        finishIfNeeded()
    }

    private func removeCandidate(_ value: Int, around index: Int, in session: inout SudokuSession) {
        let row = index / 9
        let column = index % 9
        let boxRow = (row / 3) * 3
        let boxColumn = (column / 3) * 3
        for offset in 0..<9 {
            session.candidates[row * 9 + offset].remove(value)
            session.candidates[offset * 9 + column].remove(value)
        }
        for rowOffset in 0..<3 {
            for columnOffset in 0..<3 {
                session.candidates[(boxRow + rowOffset) * 9 + boxColumn + columnOffset].remove(value)
            }
        }
    }

    private func finishIfNeeded() {
        guard var session, session.entries == session.puzzle.solution, !session.completed else { return }
        session = progress.completeSudoku(session)
        self.session = session
        showingResults = true
        feedbackCorrect = true
        feedbackSignal += 1
    }

    private func pauseAndSave() {
        guard var session else { return }
        session.pause(at: Date())
        self.session = session
        progress.saveSudoku(session)
    }

    private func playChord(_ value: Int, palette: HarmonicPalette) {
        for midi in palette.chord(for: value).midiNotes { player.play(midi: midi) }
    }

    private func playRow(_ row: Int, session: SudokuSession) {
        for column in 0..<9 {
            let value = session.puzzle.solution[row * 9 + column]
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(column) * 0.42) {
                playChord(value, palette: session.puzzle.palette)
            }
        }
    }
}

private struct SudokuBoardView: View {
    let session: SudokuSession
    @Binding var selectedIndex: Int?

    var body: some View {
        GeometryReader { geometry in
            let cellSize = geometry.size.width / 9
            ZStack(alignment: .topLeading) {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(cellSize), spacing: 0), count: 9), spacing: 0) {
                    ForEach(0..<81, id: \.self) { index in
                        cell(index, size: cellSize)
                    }
                }
                SudokuGridLines().allowsHitTesting(false)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay { RoundedRectangle(cornerRadius: 8).stroke(STEWTheme.ink.opacity(0.72), lineWidth: 2) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Nine by nine Harmonic Sudoku board")
    }

    private func cell(_ index: Int, size: CGFloat) -> some View {
        let entry = session.entries[index]
        let given = session.puzzle.givens[index] != nil
        let selected = selectedIndex == index
        let related = selectedIndex.map { relatedCell(index, to: $0) } ?? false
        let selectedValue = selectedIndex.flatMap { session.entries[$0] }
        let sameValue = entry != nil && entry == selectedValue
        let conflict = entry != nil && entry != session.puzzle.solution[index]
        let hinted = session.hintedIndices.contains(index)
        let chord = entry.map(session.puzzle.palette.chord(for:))

        return Button { selectedIndex = index } label: {
            Group {
                if let chord {
                    VStack(spacing: 0) {
                        Text(chord.roman).font(.system(size: 9, weight: given ? .bold : .semibold))
                        Text(chord.name).font(.system(size: 7, weight: .regular)).opacity(0.82)
                    }
                } else if !session.candidates[index].isEmpty {
                    candidateGrid(session.candidates[index])
                } else {
                    Color.clear
                }
            }
            .foregroundStyle(conflict ? Color.red : hinted ? STEWTheme.gold : given ? Color.primary : STEWTheme.ink)
            .frame(width: size, height: size)
            .background(cellColor(selected: selected, related: related, sameValue: sameValue, conflict: conflict))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel(index: index, chord: chord, given: given, conflict: conflict))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func candidateGrid(_ candidates: Set<Int>) -> some View {
        VStack(spacing: 0) {
            ForEach(0..<3, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<3, id: \.self) { column in
                        let value = row * 3 + column
                        Text(candidates.contains(value) ? (HarmonicChordToken(rawValue: value)?.compactRoman ?? "") : "")
                            .font(.system(size: 4.8, weight: .regular))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
        }
        .foregroundStyle(.secondary)
        .padding(2)
    }

    private func relatedCell(_ index: Int, to selected: Int) -> Bool {
        let row = index / 9, column = index % 9
        let selectedRow = selected / 9, selectedColumn = selected % 9
        return row == selectedRow || column == selectedColumn || (row / 3 == selectedRow / 3 && column / 3 == selectedColumn / 3)
    }

    private func cellColor(selected: Bool, related: Bool, sameValue: Bool, conflict: Bool) -> Color {
        if conflict { return Color.red.opacity(0.13) }
        if selected { return STEWTheme.gold.opacity(0.45) }
        if sameValue { return STEWTheme.gold.opacity(0.22) }
        if related { return STEWTheme.gold.opacity(0.08) }
        return Color(.secondarySystemBackground)
    }

    private func accessibilityLabel(index: Int, chord: HarmonicChord?, given: Bool, conflict: Bool) -> String {
        let position = "Row \(index / 9 + 1), column \(index % 9 + 1)"
        guard let chord else { return "\(position), empty" }
        return "\(position), \(chord.roman), \(chord.name)\(given ? ", given" : "")\(conflict ? ", conflict" : "")"
    }
}

private struct SudokuGridLines: View {
    var body: some View {
        Canvas { context, size in
            for index in 1..<9 {
                let position = CGFloat(index) * size.width / 9
                var vertical = Path(); vertical.move(to: CGPoint(x: position, y: 0)); vertical.addLine(to: CGPoint(x: position, y: size.height))
                var horizontal = Path(); horizontal.move(to: CGPoint(x: 0, y: position)); horizontal.addLine(to: CGPoint(x: size.width, y: position))
                let width: CGFloat = index.isMultiple(of: 3) ? 1.8 : 0.45
                let color = index.isMultiple(of: 3) ? STEWTheme.ink.opacity(0.72) : Color.secondary.opacity(0.35)
                context.stroke(vertical, with: .color(color), lineWidth: width)
                context.stroke(horizontal, with: .color(color), lineWidth: width)
            }
        }
    }
}

private struct HarmonicSudokuTheoryView: View {
    @Environment(\.dismiss) private var dismiss
    let palette: HarmonicPalette?

    var body: some View {
        NavigationStack {
            List {
                Section("The rule") {
                    Text("Every row, column, and 3×3 region must contain each harmonic function exactly once.")
                }
                Section("The harmonic palette") {
                    Text("I through vii° are the seven diatonic triads of a major key. V/V is the secondary dominant that points toward V. Borrowed iv adds minor-subdominant color from the parallel minor key.")
                    if let palette {
                        ForEach(palette.chords) { chord in
                            HStack {
                                Text(chord.roman).font(.headline).frame(width: 42, alignment: .leading)
                                Text(chord.name)
                                Spacer()
                                Text(role(for: chord.token)).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Section("Controls") {
                    Text("Select a cell, then choose a chord. Notes adds candidates instead. Undo restores the board without removing recorded mistakes or used hints.")
                }
            }
            .navigationTitle("How to Play")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    private func role(for token: HarmonicChordToken) -> String {
        switch token {
        case .secondaryDominant: "Secondary"
        case .borrowedMinorSubdominant: "Borrowed"
        default: "Diatonic"
        }
    }
}

private struct SudokuResultsView: View {
    @Environment(\.dismiss) private var dismiss
    let session: SudokuSession
    let continueAction: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 22) {
                HStack(spacing: 8) {
                    ForEach(0..<3, id: \.self) { index in
                        Image(systemName: index < session.stars ? "star.fill" : "star")
                            .font(.system(size: 34, weight: .light)).foregroundStyle(STEWTheme.gold)
                    }
                }
                VStack(spacing: 6) {
                    Text("Puzzle solved").font(.title.weight(.light))
                    Text("\(session.puzzle.palette.keyName) major · \(session.puzzle.difficulty.rawValue)")
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 0) {
                    resultStat("Time", GameFormatting.duration(session.elapsedSeconds))
                    Divider().frame(height: 42)
                    resultStat("Mistakes", "\(session.mistakes)")
                    Divider().frame(height: 42)
                    resultStat("Hints", "\(session.hintsUsed)")
                }
                .stewSurface()
                if session.puzzle.mode == .daily {
                    Label("Daily puzzle complete", systemImage: "calendar.badge.checkmark").foregroundStyle(STEWTheme.gold)
                }
                Button(session.puzzle.mode == .practice ? "New Puzzle" : "Return to Games") {
                    dismiss(); continueAction()
                }
                .buttonStyle(.borderedProminent).tint(STEWTheme.ink)
                .frame(maxWidth: .infinity)
            }
            .padding(24)
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
        .interactiveDismissDisabled()
        .accessibilityIdentifier("sudoku-results")
    }

    private func resultStat(_ label: String, _ value: String) -> some View {
        VStack(spacing: 3) {
            Text(value).font(.headline.monospacedDigit())
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
