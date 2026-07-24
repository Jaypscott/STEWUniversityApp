import AVFoundation
import Foundation

@MainActor
final class TonePlayer: ObservableObject {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!

    init() {
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        try? engine.start()
    }

    func play(midi: Int, duration: Double = 0.65) {
        let frames = AVAudioFrameCount(format.sampleRate * duration)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              let channel = buffer.floatChannelData?[0] else { return }
        buffer.frameLength = frames
        let frequency = 440.0 * pow(2.0, Double(midi - 69) / 12.0)
        for frame in 0..<Int(frames) {
            let progress = Double(frame) / Double(frames)
            let envelope = min(1, progress * 20) * max(0, 1 - progress)
            channel[frame] = Float(sin(2 * .pi * frequency * Double(frame) / format.sampleRate) * 0.22 * envelope)
        }
        player.scheduleBuffer(buffer, completionHandler: nil)
        if !player.isPlaying { player.play() }
    }
}

@MainActor
final class PianoSamplePlayer: NSObject, ObservableObject {
    private var players: [AVAudioPlayer] = []
    private let fileNames = ["C", "Cs", "D", "Ds", "E", "F", "Fs", "G", "Gs", "A", "As", "B"]

    override init() {
        super.init()
        try? AVAudioSession.sharedInstance().setCategory(
            .playback,
            mode: .default,
            options: [.mixWithOthers]
        )
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    func play(note: String, octave: Int) {
        players.removeAll { !$0.isPlaying }
        let normalized = ["Db": "C#", "Eb": "D#", "Gb": "F#", "Ab": "G#", "Bb": "A#"][note] ?? note
        let resourceName = "Piano_\(normalized.replacingOccurrences(of: "#", with: "s"))\(octave)"
        guard fileNames.contains(normalized.replacingOccurrences(of: "#", with: "s")),
              let url = Bundle.main.url(forResource: resourceName, withExtension: "m4a") else {
            return
        }

        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.volume = 0.88
            player.prepareToPlay()
            player.play()
            players.append(player)
        } catch {
            // A missed sample should not interrupt the visualizer interaction.
        }
    }

    func play(midi: Int) {
        let names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        play(note: names[midi % 12], octave: midi / 12 - 1)
    }
}

@MainActor
final class StringInstrumentSamplePlayer: NSObject, ObservableObject {
    private var players: [AVAudioPlayer] = []

    override init() {
        super.init()
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    func play(instrument: String, midi: Int) {
        players.removeAll { !$0.isPlaying }
        guard let url = Bundle.main.url(
            forResource: "\(instrument)_\(midi)",
            withExtension: "m4a"
        ) else { return }

        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.volume = instrument == "Bass" ? 0.92 : 0.86
            player.prepareToPlay()
            player.play()
            players.append(player)
        } catch {
            // Keep the fretboard responsive if a bundled sample cannot be loaded.
        }
    }
}
