import SwiftUI

struct VisualizerView: View {
    enum Instrument: String, CaseIterable { case piano = "Piano", guitar = "Guitar", bass = "Bass" }
    enum Material: String, CaseIterable { case scale = "Scale", chord = "Chord" }
    private let chromatic = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
    private let scaleTypes = ["major", "minor", "dorian", "mixolydian", "pentatonic"]
    private let chordTypes = ["major", "minor", "diminished", "augmented", "major7", "minor7", "dominant7"]

    @State private var instrument: Instrument = .piano
    @State private var material: Material = .scale
    @State private var root = "C"
    @State private var quality = "major"
    @State private var notes: [String] = []
    @State private var errorMessage: String?
    @State private var loading = false
    @StateObject private var player = TonePlayer()
    @StateObject private var pianoPlayer = PianoSamplePlayer()
    @StateObject private var stringPlayer = StringInstrumentSamplePlayer()
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("MUSIC THEORY").font(.caption.weight(.medium)).tracking(1.5).foregroundStyle(.secondary)
                    Text("See what you hear").font(.title.weight(.light))
                    Text("Explore scales and chords across familiar instruments.").font(.body.weight(.light)).foregroundStyle(.secondary)
                }
                Group {
                    if horizontalSizeClass == .regular && !dynamicTypeSize.isAccessibilitySize {
                        HStack(alignment: .top, spacing: 18) {
                            controls
                                .frame(width: 340)
                            result
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 18) {
                            controls
                            result
                        }
                    }
                }
            }
            .padding(18)
            .adaptiveContentWidth()
        }
        .task { await visualize() }
        .onChange(of: material) { _, value in quality = value == .scale ? "major" : "major" }
        .accessibilityIdentifier("visualizer-screen")
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 18) {
            Picker("Instrument", selection: $instrument) {
                ForEach(Instrument.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            VStack(spacing: 14) {
                Picker("Material", selection: $material) {
                    ForEach(Material.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                HStack {
                    Menu { ForEach(chromatic, id: \.self) { note in Button(note) { root = note } } } label: { selectorLabel("Root", root) }
                    Menu { ForEach(qualities, id: \.self) { item in Button(item.capitalized) { quality = item } } } label: { selectorLabel(material.rawValue, quality.capitalized) }
                }
                Button { Task { await visualize() } } label: {
                    if loading { ProgressView().frame(maxWidth: .infinity, minHeight: 44) }
                    else { Text("Visualize").frame(maxWidth: .infinity, minHeight: 44) }
                }
                .buttonStyle(.borderedProminent)
                .tint(STEWTheme.ink)
                .disabled(loading)
            }
            .stewSurface()
        }
    }

    @ViewBuilder private var result: some View {
        if let errorMessage {
            Text(errorMessage).font(.footnote).foregroundStyle(.red)
        }
        if !notes.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                Text("\(root) \(quality.capitalized)").font(.headline.weight(.regular))
                Text(notes.joined(separator: "  ·  ")).font(.title3.weight(.light)).foregroundStyle(STEWTheme.gold)
                instrumentView
                Button { playAll() } label: {
                    Label("Play notes", systemImage: "play.fill").frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
            }
            .stewSurface()
        }
    }

    private var qualities: [String] { material == .scale ? scaleTypes : chordTypes }
    private func selectorLabel(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading) { Text(title).font(.caption).foregroundStyle(.secondary); Text(value).foregroundStyle(.primary) }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).padding(.horizontal, 12)
            .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder private var instrumentView: some View {
        switch instrument {
        case .piano:
            PianoKeyboard(root: root, notes: notes, isChord: material == .chord) { note, octave in
                pianoPlayer.play(note: note, octave: octave)
            }
        case .guitar:
            Fretboard(instrument: "Guitar", tuning: [64, 59, 55, 50, 45, 40], root: root, notes: notes) { midi in
                stringPlayer.play(instrument: "Guitar", midi: midi)
            }
        case .bass:
            Fretboard(instrument: "Bass", tuning: [43, 38, 33, 28], root: root, notes: notes) { midi in
                stringPlayer.play(instrument: "Bass", midi: midi)
            }
        }
    }

    private func visualize() async {
        loading = true; errorMessage = nil
        do {
            let endpoint = material == .scale ? "scales" : "chords"
            let kindKey = material == .scale ? "scale_type" : "chord_type"
            notes = try await APIClient.shared.notes(endpoint: endpoint, body: ["root": root, kindKey: quality])
        } catch { errorMessage = error.localizedDescription }
        loading = false
    }
    private func midi(for note: String, octave: Int = 4) -> Int {
        let flats = ["Db": "C#", "Eb": "D#", "Gb": "F#", "Ab": "G#", "Bb": "A#"]
        return 12 * (octave + 1) + (chromatic.firstIndex(of: flats[note] ?? note) ?? 0)
    }
    private func play(_ note: String) { player.play(midi: midi(for: note)) }
    private func playAll() {
        for (index, note) in notes.enumerated() {
            let octave: Int
            let baseOctave = instrument == .bass ? 2 : 4
            if material == .chord,
               let rootIndex = chromatic.firstIndex(of: normalized(root)),
               let noteIndex = chromatic.firstIndex(of: normalized(note)) {
                octave = baseOctave + (rootIndex + (noteIndex - rootIndex + 12) % 12) / 12
            } else {
                octave = baseOctave
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.35) {
                if instrument == .piano {
                    pianoPlayer.play(note: note, octave: octave)
                } else {
                    let source = instrument == .guitar ? "Guitar" : "Bass"
                    stringPlayer.play(instrument: source, midi: midi(for: note, octave: octave))
                }
            }
        }
    }

    private func normalized(_ note: String) -> String {
        ["Db": "C#", "Eb": "D#", "Gb": "F#", "Ab": "G#", "Bb": "A#"][note] ?? note
    }
}

private struct PianoKeyboard: View {
    struct Key: Identifiable {
        let note: String
        let octave: Int
        var id: String { "\(note)-\(octave)" }
        var spokenName: String { note.replacingOccurrences(of: "#", with: " sharp") }
    }

    let root: String
    let notes: [String]
    let isChord: Bool
    let play: (String, Int) -> Void

    private let whiteNames = ["C", "D", "E", "F", "G", "A", "B"]
    private let blackNames = [("C#", 1), ("D#", 2), ("F#", 4), ("G#", 5), ("A#", 6)]
    private let chromatic = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
    private let whiteWidth: CGFloat = 46
    private let blackWidth: CGFloat = 29
    private let keyboardHeight: CGFloat = 174

    private var normalizedNotes: Set<String> {
        Set(notes.map(normalize))
    }

    private var voicedChordKeyIDs: Set<String> {
        guard isChord,
              let rootIndex = chromatic.firstIndex(of: normalize(root)) else { return [] }
        return Set(notes.compactMap { note in
            let normalizedNote = normalize(note)
            guard let noteIndex = chromatic.firstIndex(of: normalizedNote) else { return nil }
            let absoluteSemitone = rootIndex + (noteIndex - rootIndex + 12) % 12
            return "\(normalizedNote)-\(4 + absoluteSemitone / 12)"
        })
    }

    private var scrollTarget: String { "\(normalize(root))-4" }
    private var voicingSignature: String { "\(root)|\(isChord)|\(notes.joined(separator: ","))" }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Swipe to explore · Tap a key to play")
                .font(.caption.weight(.regular))
                .foregroundStyle(.secondary)

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    ZStack(alignment: .topLeading) {
                        HStack(spacing: 1) {
                            ForEach(whiteKeys) { key in
                                pianoKey(key, isBlack: false)
                                    .id(key.id)
                            }
                        }

                        ForEach(Array(blackKeys.enumerated()), id: \.element.id) { index, key in
                            pianoKey(key, isBlack: true)
                                .id(key.id)
                                .offset(x: blackOffset(for: index))
                                .zIndex(2)
                        }
                    }
                    .frame(width: whiteWidth * 14 + 13, height: keyboardHeight, alignment: .leading)
                    .padding(.horizontal, 2)
                }
                .onChange(of: voicingSignature, initial: true) { _, _ in
                    guard isChord else { return }
                    withAnimation(.easeInOut(duration: 0.35)) {
                        proxy.scrollTo(scrollTarget, anchor: .leading)
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Two octave piano keyboard")
    }

    private var whiteKeys: [Key] {
        [4, 5].flatMap { octave in whiteNames.map { Key(note: $0, octave: octave) } }
    }

    private var blackKeys: [Key] {
        [4, 5].flatMap { octave in blackNames.map { Key(note: $0.0, octave: octave) } }
    }

    private func blackOffset(for index: Int) -> CGFloat {
        let octave = index / blackNames.count
        let boundary = blackNames[index % blackNames.count].1
        return CGFloat(octave * 7 + boundary) * (whiteWidth + 1) - blackWidth / 2
    }

    @ViewBuilder
    private func pianoKey(_ key: Key, isBlack: Bool) -> some View {
        let highlighted = isChord ? voicedChordKeyIDs.contains(key.id) : normalizedNotes.contains(key.note)
        let isRoot = normalize(root) == key.note && (!isChord || key.octave == 4)

        Button { play(key.note, key.octave) } label: {
            VStack(spacing: 3) {
                Spacer()
                if !isBlack {
                    if isRoot {
                        Circle().fill(STEWTheme.ink).frame(width: 6, height: 6)
                    }
                    Text(key.note)
                        .font(.caption2.weight(isRoot ? .semibold : .regular))
                        .foregroundStyle(highlighted ? STEWTheme.ink : Color.secondary)
                        .padding(.bottom, 8)
                }
            }
            .frame(width: isBlack ? blackWidth : whiteWidth,
                   height: isBlack ? keyboardHeight * 0.61 : keyboardHeight)
            .background(keyColor(isBlack: isBlack, highlighted: highlighted, isRoot: isRoot))
            .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 5, bottomTrailingRadius: 5))
            .overlay {
                UnevenRoundedRectangle(bottomLeadingRadius: 5, bottomTrailingRadius: 5)
                    .stroke(isRoot ? STEWTheme.gold : Color.black.opacity(isBlack ? 0.65 : 0.22),
                            lineWidth: isRoot ? 3 : 0.7)
            }
            .shadow(color: .black.opacity(isBlack ? 0.32 : 0.12), radius: isBlack ? 3 : 1, y: isBlack ? 3 : 1)
        }
        .buttonStyle(PianoKeyButtonStyle())
        .accessibilityLabel("Play \(key.spokenName) \(key.octave)\(isRoot ? ", root note" : "")")
        .accessibilityValue(highlighted ? "Highlighted" : "Not highlighted")
    }

    private func keyColor(isBlack: Bool, highlighted: Bool, isRoot: Bool) -> Color {
        if isRoot { return STEWTheme.gold }
        if highlighted { return isBlack ? STEWTheme.gold.opacity(0.88) : STEWTheme.gold.opacity(0.62) }
        return isBlack ? Color(red: 0.055, green: 0.06, blue: 0.07) : Color.white
    }

    private func normalize(_ note: String) -> String {
        ["Db": "C#", "Eb": "D#", "Gb": "F#", "Ab": "G#", "Bb": "A#"][note] ?? note
    }
}

private struct PianoKeyButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(x: 1, y: configuration.isPressed ? 0.975 : 1, anchor: .top)
            .brightness(configuration.isPressed ? -0.08 : 0)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

private struct Fretboard: View {
    let instrument: String
    let tuning: [Int]
    let root: String
    let notes: [String]
    let play: (Int) -> Void

    private let chromatic = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
    private let fretCount = 12
    private let boardWidth: CGFloat = 760
    private let nutX: CGFloat = 48

    private var boardHeight: CGFloat { instrument == "Bass" ? 210 : 226 }
    private var topInset: CGFloat { 32 }
    private var bottomInset: CGFloat { 34 }
    private var stringSpacing: CGFloat {
        (boardHeight - topInset - bottomInset) / CGFloat(max(tuning.count - 1, 1))
    }
    private var highlightedNotes: Set<String> { Set(notes.map(normalize)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Swipe across the neck · Tap any string position")
                .font(.caption.weight(.regular))
                .foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 9)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.16, green: 0.085, blue: 0.045),
                                    Color(red: 0.28, green: 0.145, blue: 0.07),
                                    Color(red: 0.13, green: 0.065, blue: 0.035),
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 9)
                                .stroke(Color.black.opacity(0.5), lineWidth: 1)
                        }

                    woodGrain
                    fretLines
                    positionMarkers
                    strings
                    noteButtons
                }
                .frame(width: boardWidth, height: boardHeight)
                .padding(.horizontal, 2)
            }
            .accessibilityLabel("\(instrument) fretboard, open strings through fret twelve")
        }
    }

    private var woodGrain: some View {
        ZStack {
            ForEach(0..<8, id: \.self) { line in
                Rectangle()
                    .fill(Color.white.opacity(line.isMultiple(of: 2) ? 0.025 : 0.014))
                    .frame(width: boardWidth - 10, height: 1)
                    .offset(x: 5, y: 18 + CGFloat(line) * 25)
            }
        }
    }

    private var fretLines: some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(Color(red: 0.85, green: 0.82, blue: 0.72))
                .frame(width: 5, height: boardHeight)
                .offset(x: nutX - 2.5)

            ForEach(1...fretCount, id: \.self) { fret in
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [.white.opacity(0.8), .gray.opacity(0.8), .white.opacity(0.45)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: 2, height: boardHeight - 4)
                    .offset(x: fretLineX(fret), y: 2)

                Text("\(fret)")
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.48))
                    .position(x: fretCenterX(fret), y: boardHeight - 13)
            }
        }
    }

    private var positionMarkers: some View {
        ZStack {
            ForEach([3, 5, 7, 9], id: \.self) { fret in
                Circle()
                    .fill(Color.white.opacity(0.3))
                    .frame(width: 10, height: 10)
                    .position(x: fretCenterX(fret), y: boardHeight / 2)
            }
            ForEach([-1, 1], id: \.self) { direction in
                Circle()
                    .fill(Color.white.opacity(0.34))
                    .frame(width: 10, height: 10)
                    .position(x: fretCenterX(12), y: boardHeight / 2 + CGFloat(direction) * 24)
            }
        }
    }

    private var strings: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(tuning.enumerated()), id: \.offset) { index, _ in
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [.white.opacity(0.88), .gray.opacity(0.9), .white.opacity(0.58)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: boardWidth, height: gauge(for: index))
                    .shadow(color: .black.opacity(0.55), radius: 1, y: 1.5)
                    .position(x: boardWidth / 2, y: stringY(index))
            }
        }
    }

    private var noteButtons: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(tuning.enumerated()), id: \.offset) { stringIndex, openMidi in
                ForEach(0...fretCount, id: \.self) { fret in
                    let midi = openMidi + fret
                    let note = chromatic[midi % 12]
                    let highlighted = highlightedNotes.contains(note)
                    let isRoot = normalize(root) == note

                    Button { play(midi) } label: {
                        Text(highlighted ? note.replacingOccurrences(of: "#", with: "♯") : "")
                            .font(.system(size: 9, weight: isRoot ? .bold : .semibold, design: .rounded))
                            .foregroundStyle(STEWTheme.ink)
                            .frame(width: instrument == "Bass" ? 32 : 29,
                                   height: instrument == "Bass" ? 32 : 29)
                            .background(
                                highlighted ? (isRoot ? STEWTheme.gold : STEWTheme.gold.opacity(0.84)) : Color.clear,
                                in: Circle()
                            )
                            .overlay {
                                if isRoot && highlighted {
                                    Circle().stroke(Color.white.opacity(0.9), lineWidth: 2)
                                }
                            }
                            .contentShape(Circle())
                    }
                    .buttonStyle(FretNoteButtonStyle())
                    .position(x: fret == 0 ? nutX / 2 : fretCenterX(fret), y: stringY(stringIndex))
                    .accessibilityLabel(
                        "\(instrument) string \(spokenNote(openMidi)), fret \(fret), play \(spokenNote(midi))"
                    )
                    .accessibilityValue(highlighted ? (isRoot ? "Root note" : "Highlighted") : "Not highlighted")
                }
            }
        }
    }

    private func fretLineX(_ fret: Int) -> CGFloat {
        let usableWidth = boardWidth - nutX - 10
        let raw = 1 - pow(2, -Double(fret) / 12)
        let maxRaw = 1 - pow(2, -Double(fretCount) / 12)
        return nutX + usableWidth * CGFloat(raw / maxRaw)
    }

    private func fretCenterX(_ fret: Int) -> CGFloat {
        let previous = fret == 1 ? nutX : fretLineX(fret - 1)
        return (previous + fretLineX(fret)) / 2
    }

    private func stringY(_ index: Int) -> CGFloat {
        topInset + CGFloat(index) * stringSpacing
    }

    private func gauge(for index: Int) -> CGFloat {
        if instrument == "Bass" {
            return [2.2, 2.9, 3.6, 4.4][index]
        }
        return [1.0, 1.2, 1.45, 1.8, 2.2, 2.7][index]
    }

    private func normalize(_ note: String) -> String {
        ["Db": "C#", "Eb": "D#", "Gb": "F#", "Ab": "G#", "Bb": "A#"][note] ?? note
    }

    private func spokenNote(_ midi: Int) -> String {
        let note = chromatic[midi % 12].replacingOccurrences(of: "#", with: " sharp")
        return "\(note) \(midi / 12 - 1)"
    }
}

private struct FretNoteButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.84 : 1)
            .brightness(configuration.isPressed ? -0.08 : 0)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}
