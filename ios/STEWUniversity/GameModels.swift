import Foundation

enum GameDestination: String, CaseIterable, Identifiable {
    case harmonicSudoku = "Harmonic Sudoku"
    case melodyMemory = "Melody Memory"

    var id: String { rawValue }
}

enum SudokuMode: String, Codable, CaseIterable, Identifiable {
    case daily = "Daily"
    case practice = "Practice"
    var id: String { rawValue }
}

enum SudokuDifficulty: String, Codable, CaseIterable, Identifiable {
    case easy = "Easy"
    case medium = "Medium"
    case hard = "Hard"

    var id: String { rawValue }
    var clueCount: Int {
        switch self {
        case .easy: 45
        case .medium: 36
        case .hard: 30
        }
    }
}

enum HarmonicChordToken: Int, Codable, CaseIterable, Identifiable {
    case tonic, supertonic, mediant, subdominant, dominant, submediant, leadingTone
    case secondaryDominant, borrowedMinorSubdominant

    var id: Int { rawValue }
    var roman: String {
        switch self {
        case .tonic: "I"
        case .supertonic: "ii"
        case .mediant: "iii"
        case .subdominant: "IV"
        case .dominant: "V"
        case .submediant: "vi"
        case .leadingTone: "vii°"
        case .secondaryDominant: "V/V"
        case .borrowedMinorSubdominant: "iv"
        }
    }

    var compactRoman: String {
        switch self {
        case .leadingTone: "vii"
        case .secondaryDominant: "V/V"
        default: roman
        }
    }

    fileprivate var degreeOffset: Int {
        switch self {
        case .tonic: 0
        case .supertonic, .secondaryDominant: 2
        case .mediant: 4
        case .subdominant, .borrowedMinorSubdominant: 5
        case .dominant: 7
        case .submediant: 9
        case .leadingTone: 11
        }
    }

    fileprivate var intervals: [Int] {
        switch self {
        case .supertonic, .mediant, .submediant, .borrowedMinorSubdominant: [0, 3, 7]
        case .leadingTone: [0, 3, 6]
        default: [0, 4, 7]
        }
    }
}

struct HarmonicChord: Equatable, Identifiable {
    let token: HarmonicChordToken
    let roman: String
    let name: String
    let midiNotes: [Int]
    var id: Int { token.rawValue }
}

struct HarmonicPalette: Equatable {
    let keyIndex: Int

    static let keyNames = ["C", "G", "D", "A", "E", "B", "F#", "Db", "Ab", "Eb", "Bb", "F"]
    private static let keyPitchClasses = [0, 7, 2, 9, 4, 11, 6, 1, 8, 3, 10, 5]
    private static let rootSpellings = [
        ["C", "D", "E", "F", "G", "A", "B", "D", "F"],
        ["G", "A", "B", "C", "D", "E", "F#", "A", "C"],
        ["D", "E", "F#", "G", "A", "B", "C#", "E", "G"],
        ["A", "B", "C#", "D", "E", "F#", "G#", "B", "D"],
        ["E", "F#", "G#", "A", "B", "C#", "D#", "F#", "A"],
        ["B", "C#", "D#", "E", "F#", "G#", "A#", "C#", "E"],
        ["F#", "G#", "A#", "B", "C#", "D#", "E#", "G#", "B"],
        ["Db", "Eb", "F", "Gb", "Ab", "Bb", "C", "Eb", "Gb"],
        ["Ab", "Bb", "C", "Db", "Eb", "F", "G", "Bb", "Db"],
        ["Eb", "F", "G", "Ab", "Bb", "C", "D", "F", "Ab"],
        ["Bb", "C", "D", "Eb", "F", "G", "A", "C", "Eb"],
        ["F", "G", "A", "Bb", "C", "D", "E", "G", "Bb"]
    ]

    init(keyIndex: Int) {
        self.keyIndex = max(0, min(Self.keyNames.count - 1, keyIndex))
    }

    var keyName: String { Self.keyNames[keyIndex] }
    var chords: [HarmonicChord] { HarmonicChordToken.allCases.map(chord(for:)) }

    func chord(for value: Int) -> HarmonicChord {
        chord(for: HarmonicChordToken(rawValue: value) ?? .tonic)
    }

    func chord(for token: HarmonicChordToken) -> HarmonicChord {
        let root = Self.rootSpellings[keyIndex][token.rawValue]
        let suffix: String
        switch token {
        case .supertonic, .mediant, .submediant, .borrowedMinorSubdominant: suffix = "m"
        case .leadingTone: suffix = "°"
        default: suffix = ""
        }
        let pitchClass = (Self.keyPitchClasses[keyIndex] + token.degreeOffset) % 12
        let rootMIDI = 60 + pitchClass
        return HarmonicChord(
            token: token,
            roman: token.roman,
            name: root + suffix,
            midiNotes: token.intervals.map { rootMIDI + $0 }
        )
    }
}

struct HarmonicSudokuPuzzle: Codable, Equatable, Identifiable {
    let id: String
    let mode: SudokuMode
    let dayKey: String?
    let difficulty: SudokuDifficulty
    let keyIndex: Int
    let solution: [Int]
    let givens: [Int?]

    var palette: HarmonicPalette { HarmonicPalette(keyIndex: keyIndex) }
}

struct SudokuSnapshot: Codable, Equatable {
    let entries: [Int?]
    let candidates: [Set<Int>]
    let hintedIndices: Set<Int>
    let mistakes: Int
    let hintsUsed: Int
}

struct SudokuSession: Codable, Equatable {
    var puzzle: HarmonicSudokuPuzzle
    var entries: [Int?]
    var candidates: [Set<Int>]
    var hintedIndices: Set<Int>
    var mistakes: Int
    var hintsUsed: Int
    var elapsedSeconds: Int
    var startedAt: Date?
    var completed: Bool
    var completionRecorded: Bool
    var undoHistory: [SudokuSnapshot]

    init(puzzle: HarmonicSudokuPuzzle) {
        self.puzzle = puzzle
        entries = puzzle.givens
        candidates = Array(repeating: [], count: 81)
        hintedIndices = []
        mistakes = 0
        hintsUsed = 0
        elapsedSeconds = 0
        startedAt = nil
        completed = false
        completionRecorded = false
        undoHistory = []
    }

    var stars: Int {
        if mistakes == 0 && hintsUsed == 0 { return 3 }
        if mistakes <= 3 && hintsUsed <= 1 { return 2 }
        return 1
    }

    func elapsed(at date: Date) -> Int {
        elapsedSeconds + (startedAt.map { max(0, Int(date.timeIntervalSince($0))) } ?? 0)
    }

    mutating func begin(at date: Date) {
        guard !completed, startedAt == nil else { return }
        startedAt = date
    }

    mutating func pause(at date: Date) {
        guard let startedAt else { return }
        elapsedSeconds += max(0, Int(date.timeIntervalSince(startedAt)))
        self.startedAt = nil
    }

    mutating func pushUndo() {
        undoHistory.append(SudokuSnapshot(
            entries: entries,
            candidates: candidates,
            hintedIndices: hintedIndices,
            mistakes: mistakes,
            hintsUsed: hintsUsed
        ))
        if undoHistory.count > 40 { undoHistory.removeFirst() }
    }

    mutating func undo() {
        guard let snapshot = undoHistory.popLast() else { return }
        entries = snapshot.entries
        candidates = snapshot.candidates
        hintedIndices = snapshot.hintedIndices
    }
}

struct HarmonicSudokuStats: Codable, Equatable {
    var solvedCount = 0
    var currentDailyStreak = 0
    var longestDailyStreak = 0
    var lastDailyCompletionDay: String?
    var completedDailyDays: [String] = []
    var bestUnassistedSeconds: [String: Int] = [:]
    var completedPuzzleIDs: Set<String> = []
}

enum MelodyDifficulty: String, Codable, CaseIterable, Identifiable {
    case easy = "Easy"
    case medium = "Medium"
    case hard = "Hard"

    var id: String { rawValue }
    var notePool: [Int] {
        switch self {
        case .easy: [60, 62, 64, 67, 69]
        case .medium: [60, 62, 64, 65, 67, 69, 71, 72]
        case .hard: Array(60...72)
        }
    }
    var noteSpacing: TimeInterval {
        switch self {
        case .easy: 0.55
        case .medium: 0.42
        case .hard: 0.32
        }
    }
}

enum MelodyInputOutcome: Equatable {
    case correctNote
    case roundComplete(points: Int)
    case retry
    case gameOver
}

protocol MelodyNoteGenerating: AnyObject {
    func nextNote(from pool: [Int], sequence: [Int]) -> Int
}

final class RandomMelodyNoteGenerator: MelodyNoteGenerating {
    func nextNote(from pool: [Int], sequence: [Int]) -> Int {
        guard !pool.isEmpty else { return 60 }
        var allowed = pool
        if sequence.count >= 2, sequence.suffix(2).allSatisfy({ $0 == sequence.last }) {
            allowed.removeAll { $0 == sequence.last }
        }
        return allowed.randomElement() ?? pool[0]
    }
}

struct MelodyMemorySession: Equatable {
    let difficulty: MelodyDifficulty
    var sequence: [Int]
    var inputIndex: Int
    var hearts: Int
    var score: Int
    var completedRounds: Int
    var replayUsedThisRound: Bool

    init(difficulty: MelodyDifficulty, generator: MelodyNoteGenerating) {
        self.difficulty = difficulty
        sequence = []
        inputIndex = 0
        hearts = 3
        score = 0
        completedRounds = 0
        replayUsedThisRound = false
        for _ in 0..<3 { sequence.append(generator.nextNote(from: difficulty.notePool, sequence: sequence)) }
    }

    mutating func submit(_ midi: Int) -> MelodyInputOutcome {
        guard hearts > 0, inputIndex < sequence.count else { return .gameOver }
        guard midi == sequence[inputIndex] else {
            hearts -= 1
            inputIndex = 0
            return hearts == 0 ? .gameOver : .retry
        }
        inputIndex += 1
        guard inputIndex == sequence.count else { return .correctNote }
        let fullPoints = sequence.count * 10
        let points = replayUsedThisRound ? fullPoints / 2 : fullPoints
        score += points
        completedRounds += 1
        return .roundComplete(points: points)
    }

    mutating func advance(using generator: MelodyNoteGenerating) {
        sequence.append(generator.nextNote(from: difficulty.notePool, sequence: sequence))
        inputIndex = 0
        replayUsedThisRound = false
    }

    mutating func useReplay() -> Bool {
        guard !replayUsedThisRound, hearts > 0 else { return false }
        replayUsedThisRound = true
        inputIndex = 0
        return true
    }
}

struct MelodyMemoryStats: Codable, Equatable {
    var gamesPlayed = 0
    var highScore = 0
    var longestSequence = 0
    var totalCorrectRounds = 0
    var bestScores: [String: Int] = [:]
}

struct GameProfile: Codable, Equatable {
    var version = 1
    var sudoku = HarmonicSudokuStats()
    var melody = MelodyMemoryStats()
    var activeDailySudoku: SudokuSession?
    var activePracticeSudoku: SudokuSession?

    enum CodingKeys: String, CodingKey {
        case version, sudoku, melody, activeDailySudoku, activePracticeSudoku
    }

    init() {}

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        version = try values.decodeIfPresent(Int.self, forKey: .version) ?? 1
        sudoku = try values.decodeIfPresent(HarmonicSudokuStats.self, forKey: .sudoku) ?? HarmonicSudokuStats()
        melody = try values.decodeIfPresent(MelodyMemoryStats.self, forKey: .melody) ?? MelodyMemoryStats()
        activeDailySudoku = try values.decodeIfPresent(SudokuSession.self, forKey: .activeDailySudoku)
        activePracticeSudoku = try values.decodeIfPresent(SudokuSession.self, forKey: .activePracticeSudoku)
        version = 1
    }
}

struct StableSeededRandomNumberGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: String) {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in seed.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        state = hash == 0 ? 0x9E3779B97F4A7C15 : hash
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
        value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
        return value ^ (value >> 31)
    }
}

struct HarmonicSudokuGenerator {
    static let puzzleVersion = 1

    func daily(dayKey: String) -> HarmonicSudokuPuzzle {
        generate(seed: "stew-sudoku-v\(Self.puzzleVersion)-\(dayKey)", mode: .daily, dayKey: dayKey, difficulty: .medium)
    }

    func practice(difficulty: SudokuDifficulty, seed: String = UUID().uuidString) -> HarmonicSudokuPuzzle {
        generate(seed: "stew-sudoku-v\(Self.puzzleVersion)-practice-\(seed)", mode: .practice, dayKey: nil, difficulty: difficulty)
    }

    func generate(seed: String, mode: SudokuMode, dayKey: String?, difficulty: SudokuDifficulty) -> HarmonicSudokuPuzzle {
        var random = StableSeededRandomNumberGenerator(seed: seed)
        let rows = shuffledUnits(using: &random)
        let columns = shuffledUnits(using: &random)
        var symbols = Array(0..<9)
        symbols.shuffle(using: &random)
        let solution = rows.flatMap { row in
            columns.map { column in
                symbols[(row * 3 + row / 3 + column) % 9]
            }
        }
        var givens = solution.map(Optional.some)
        var positions = Array(0..<81)
        positions.shuffle(using: &random)
        for position in positions where givens.compactMap({ $0 }).count > difficulty.clueCount {
            let previous = givens[position]
            givens[position] = nil
            if Self.solutionCount(for: givens, limit: 2) != 1 { givens[position] = previous }
        }
        return HarmonicSudokuPuzzle(
            id: seed,
            mode: mode,
            dayKey: dayKey,
            difficulty: difficulty,
            keyIndex: Int.random(in: 0..<HarmonicPalette.keyNames.count, using: &random),
            solution: solution,
            givens: givens
        )
    }

    private func shuffledUnits(using random: inout StableSeededRandomNumberGenerator) -> [Int] {
        var groups = [0, 1, 2]
        groups.shuffle(using: &random)
        return groups.flatMap { group in
            var values = [0, 1, 2]
            values.shuffle(using: &random)
            return values.map { group * 3 + $0 }
        }
    }

    static func isValid(solution: [Int]) -> Bool {
        guard solution.count == 81 else { return false }
        let expected = Set(0..<9)
        for index in 0..<9 {
            if Set((0..<9).map { solution[index * 9 + $0] }) != expected { return false }
            if Set((0..<9).map { solution[$0 * 9 + index] }) != expected { return false }
        }
        for boxRow in 0..<3 {
            for boxColumn in 0..<3 {
                let values = (0..<3).flatMap { row in
                    (0..<3).map { column in solution[(boxRow * 3 + row) * 9 + boxColumn * 3 + column] }
                }
                if Set(values) != expected { return false }
            }
        }
        return true
    }

    static func solutionCount(for board: [Int?], limit: Int = 2) -> Int {
        guard board.count == 81 else { return 0 }
        var board = board
        var count = 0
        solve(&board, count: &count, limit: limit)
        return count
    }

    private static func solve(_ board: inout [Int?], count: inout Int, limit: Int) {
        guard count < limit else { return }
        guard let index = bestEmptyIndex(in: board) else {
            count += 1
            return
        }
        for value in candidates(for: index, board: board) {
            board[index] = value
            solve(&board, count: &count, limit: limit)
            board[index] = nil
            if count >= limit { return }
        }
    }

    private static func bestEmptyIndex(in board: [Int?]) -> Int? {
        board.indices.filter { board[$0] == nil }.min {
            candidates(for: $0, board: board).count < candidates(for: $1, board: board).count
        }
    }

    private static func candidates(for index: Int, board: [Int?]) -> [Int] {
        let row = index / 9
        let column = index % 9
        var used = Set<Int>()
        for offset in 0..<9 {
            if let value = board[row * 9 + offset] { used.insert(value) }
            if let value = board[offset * 9 + column] { used.insert(value) }
        }
        let boxRow = (row / 3) * 3
        let boxColumn = (column / 3) * 3
        for rowOffset in 0..<3 {
            for columnOffset in 0..<3 {
                if let value = board[(boxRow + rowOffset) * 9 + boxColumn + columnOffset] { used.insert(value) }
            }
        }
        return (0..<9).filter { !used.contains($0) }
    }
}
