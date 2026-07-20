import SwiftUI

struct JamView: View {
    @Binding private var selectedInstrument: JamInstrument?
    @StateObject private var viewModel: JamViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private let columns = [GridItem(.adaptive(minimum: 92), spacing: 12)]

    init(
        selectedInstrument: Binding<JamInstrument?>,
        catalogProvider: any JamCatalogProviding = EmptyJamCatalogProvider()
    ) {
        _selectedInstrument = selectedInstrument
        _viewModel = StateObject(wrappedValue: JamViewModel(provider: catalogProvider))
    }

    var body: some View {
        ScrollView {
            Group {
                if horizontalSizeClass == .regular && !dynamicTypeSize.isAccessibilitySize {
                    HStack(alignment: .top, spacing: 24) {
                        VStack(alignment: .leading, spacing: 24) {
                            header
                            instrumentPicker
                        }
                        .frame(maxWidth: 440, alignment: .topLeading)

                        backingTracks
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                } else {
                    LazyVStack(alignment: .leading, spacing: 24) {
                        header
                        instrumentPicker
                        backingTracks
                    }
                }
            }
            .padding(18)
            .adaptiveContentWidth()
            .accessibilityIdentifier("jam-screen")
        }
        .background(Color(.systemBackground))
        .task { await viewModel.loadIfNeeded() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "waveform")
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(STEWTheme.gold)
                .accessibilityHidden(true)
            Text("JAM")
                .font(.caption.weight(.medium))
                .tracking(1.5)
                .foregroundStyle(.secondary)
            Text("Have fun Jamming")
                .font(.system(.largeTitle, weight: .light))
            Text("Pick an instrument, find your groove, and enjoy making music your way.")
                .font(.body.weight(.light))
                .foregroundStyle(.secondary)
                .lineSpacing(4)
        }
    }

    private var instrumentPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What are you playing?")
                .font(.title3.weight(.regular))

            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(JamInstrument.allCases) { instrument in
                    instrumentButton(instrument)
                }
            }
        }
    }

    private func instrumentButton(_ instrument: JamInstrument) -> some View {
        let selected = selectedInstrument == instrument
        return Button {
            withAnimation(reduceMotion ? nil : .snappy) {
                selectedInstrument = instrument
            }
        } label: {
            VStack(spacing: 8) {
                Image(systemName: instrument.symbol)
                    .font(.system(size: 24, weight: .light))
                    .frame(height: 28)
                Text(instrument.title)
                    .font(.footnote.weight(.regular))
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(selected ? STEWTheme.gold : .primary)
            .frame(maxWidth: .infinity, minHeight: 88)
            .padding(.horizontal, 8)
            .background(
                selected ? STEWTheme.gold.opacity(0.16) : Color(.secondarySystemBackground),
                in: RoundedRectangle(cornerRadius: 16)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        selected ? STEWTheme.gold : Color(.separator).opacity(0.45),
                        lineWidth: selected ? 1.5 : 0.5
                    )
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("jam-instrument-\(instrument.rawValue)")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityHint("Shows backing tracks for \(instrument.title)")
    }

    private var backingTracks: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Backing tracks")
                .font(.title3.weight(.regular))

            switch viewModel.state {
            case .idle, .loading:
                statusCard(symbol: "waveform", title: "Loading backing tracks…") {
                    ProgressView().controlSize(.small)
                }
            case let .failed(message):
                statusCard(
                    symbol: "exclamationmark.triangle",
                    title: "Couldn’t load tracks",
                    message: message
                ) {
                    Button("Try again") {
                        Task { await viewModel.retry() }
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("jam-retry")
                }
            case .loaded:
                loadedContent
            }
        }
    }

    @ViewBuilder private var loadedContent: some View {
        if let selectedInstrument {
            let tracks = viewModel.tracks(for: selectedInstrument)
            if tracks.isEmpty {
                statusCard(
                    symbol: selectedInstrument.symbol,
                    title: "\(selectedInstrument.title) tracks are on the way",
                    message: "New backing tracks for this instrument will appear here when they’re ready."
                )
                .accessibilityIdentifier("jam-empty-selected")
            } else {
                ForEach(tracks) { track in
                    trackCard(track)
                }
            }
        } else {
            statusCard(
                symbol: "hand.tap",
                title: "Choose an instrument",
                message: "Select what you’re playing to see backing tracks made for your part."
            )
            .accessibilityIdentifier("jam-empty-unselected")
        }
    }

    private func trackCard(_ track: JamTrack) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(track.title).font(.headline.weight(.regular))
                Spacer()
                Text(track.difficulty.title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(STEWTheme.gold)
            }
            Text("\(track.genre) · \(track.musicalKey) · \(track.bpm) BPM")
                .font(.subheadline.weight(.light))
                .foregroundStyle(.secondary)
            HStack {
                Label(formattedDuration(track.duration), systemImage: "clock")
                if let prompt = track.practicePrompt {
                    Spacer()
                    Label(prompt, systemImage: "sparkles")
                        .lineLimit(1)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .stewSurface()
        .accessibilityIdentifier("jam-track-\(track.id)")
    }

    private func statusCard<Accessory: View>(
        symbol: String,
        title: String,
        message: String? = nil,
        @ViewBuilder accessory: () -> Accessory
    ) -> some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(STEWTheme.gold)
                .accessibilityHidden(true)
            Text(title)
                .font(.headline.weight(.regular))
                .multilineTextAlignment(.center)
            if let message {
                Text(message)
                    .font(.subheadline.weight(.light))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            accessory()
        }
        .frame(maxWidth: .infinity, minHeight: 148)
        .stewSurface()
    }

    private func statusCard(
        symbol: String,
        title: String,
        message: String? = nil
    ) -> some View {
        statusCard(symbol: symbol, title: title, message: message) { EmptyView() }
    }

    private func formattedDuration(_ duration: TimeInterval) -> String {
        let totalSeconds = max(0, Int(duration.rounded()))
        return String(format: "%d:%02d", totalSeconds / 60, totalSeconds % 60)
    }
}
