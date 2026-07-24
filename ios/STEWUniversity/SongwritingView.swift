import SwiftUI

@MainActor
final class SongwritingViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var draft = ""
    @Published var quota: Quota?
    @Published var errorMessage: String?
    @Published var isSending = false
    @Published var disabledUntil: Date?
    @Published private(set) var typingMessageID: UUID?

    private let storageKey = "stew.songwriting.messages"

    init() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let stored = try? JSONDecoder().decode([ChatMessage].self, from: data) {
            messages = Array(stored.suffix(40))
        }
    }

    var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        draft.count <= 1200 && !isSending && typingMessageID == nil &&
        (disabledUntil ?? .distantPast) <= Date()
    }

    func send() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= 1200 else { return }
        let prior = messages
        messages.append(ChatMessage(role: .user, content: text))
        draft = ""
        errorMessage = nil
        isSending = true
        save()
        do {
            let result = try await APIClient.shared.chat(message: text, mode: .songwriting, history: prior)
            let response = ChatMessage(role: .assistant, content: result.0)
            messages.append(response)
            typingMessageID = response.id
            quota = result.1
        } catch let APIError.rateLimited(message, serverQuota, retryAfter) {
            errorMessage = message
            quota = serverQuota ?? quota
            disabledUntil = Date().addingTimeInterval(retryAfter)
        } catch {
            errorMessage = error.localizedDescription
        }
        isSending = false
        save()
    }

    func clear() {
        messages.removeAll()
        typingMessageID = nil
        errorMessage = nil
        save()
    }

    func finishTyping(messageID: UUID) {
        guard typingMessageID == messageID else { return }
        typingMessageID = nil
    }

    private func save() {
        if let data = try? JSONEncoder().encode(Array(messages.suffix(40))) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
}

struct SongwritingView: View {
    @StateObject private var model = SongwritingViewModel()
    @FocusState private var focused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            if model.messages.isEmpty { welcome } else { conversation }
            composer
        }
        .background(Color(.systemBackground))
        .accessibilityIdentifier("songwriting-screen")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if !model.messages.isEmpty {
                    Button("Clear", action: model.clear).fontWeight(.regular)
                }
            }
        }
    }

    private var welcome: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Spacer(minLength: 54)
                Image(systemName: "music.note.house")
                    .font(.system(size: 32, weight: .light)).foregroundStyle(STEWTheme.gold)
                Text("What can I help\nyou write?")
                    .font(.system(.largeTitle, design: .default, weight: .light))
                Text("Explore melody, harmony, lyrics, structure, and creative direction with your songwriting assistant.")
                    .font(.body.weight(.light)).foregroundStyle(.secondary).lineSpacing(4)
                SuggestionGrid { suggestion in model.draft = suggestion; focused = true }
                Spacer(minLength: 20)
            }
            .padding(24)
            .adaptiveContentWidth(STEWTheme.readingWidth, alignment: .leading)
        }
    }

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 18) {
                    ForEach(model.messages) { message in
                        MessageBubble(
                            message: message,
                            animatesResponse: message.id == model.typingMessageID && !reduceMotion,
                            onTypingProgress: {
                                proxy.scrollTo(message.id, anchor: .bottom)
                            },
                            onTypingComplete: {
                                model.finishTyping(messageID: message.id)
                            }
                        )
                        .id(message.id)
                    }
                    if model.isSending {
                        HStack { ProgressView(); Text("Thinking…").foregroundStyle(.secondary); Spacer() }
                    }
                }
                .padding(18)
                .adaptiveContentWidth(STEWTheme.readingWidth)
            }
            .onChange(of: model.messages.count) { _, _ in
                if let id = model.messages.last?.id { withAnimation { proxy.scrollTo(id, anchor: .bottom) } }
            }
        }
    }

    private var composer: some View {
        VStack(spacing: 8) {
            if let error = model.errorMessage {
                Text(error).font(.footnote).foregroundStyle(.red).frame(maxWidth: .infinity, alignment: .leading)
            }
            if let quota = model.quota {
                Text("\(quota.remaining) of \(quota.limit) AI requests remaining")
                    .font(.caption.weight(.regular)).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel("\(quota.remaining) of \(quota.limit) AI requests remaining today")
            }
            HStack(alignment: .bottom, spacing: 10) {
                TextField("Describe your song idea…", text: $model.draft, axis: .vertical)
                    .lineLimit(1...5).focused($focused).textFieldStyle(.plain)
                    .padding(.horizontal, 14).padding(.vertical, 12)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
                    .onSubmit { if model.canSend { Task { await model.send() } } }
                Button { Task { await model.send() } } label: {
                    Image(systemName: "arrow.up").fontWeight(.semibold).frame(width: 44, height: 44)
                        .background(model.canSend ? STEWTheme.ink : Color(.tertiarySystemFill), in: Circle())
                        .foregroundStyle(model.canSend ? Color.white : Color.secondary)
                }
                .disabled(!model.canSend).accessibilityLabel("Send message")
            }
            if model.draft.count > 1000 {
                Text("\(model.draft.count) / 1,200").font(.caption2).foregroundStyle(model.draft.count > 1200 ? .red : .secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(.horizontal, 14).padding(.top, 10).padding(.bottom, 8)
        .adaptiveContentWidth(STEWTheme.readingWidth)
        .background(.bar)
    }
}

private struct MessageBubble: View {
    let message: ChatMessage
    let animatesResponse: Bool
    let onTypingProgress: () -> Void
    let onTypingComplete: () -> Void

    private var displayedContent: String {
        message.content.stewPlainText
    }

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 42) }
            TypewriterText(
                text: displayedContent,
                animates: message.role == .assistant && animatesResponse,
                onProgress: onTypingProgress,
                onComplete: onTypingComplete
            )
                .font(.body.weight(.regular)).textSelection(.enabled)
                .padding(14)
                .background(message.role == .user ? STEWTheme.gold.opacity(0.18) : Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 17))
            if message.role == .assistant { Spacer(minLength: 24) }
        }.accessibilityLabel(
            "\(message.role == .user ? "You" : "Songwriting Assistant"): \(displayedContent)"
        )
    }
}

private struct SuggestionGrid: View {
    let choose: (String) -> Void
    private let suggestions = ["Build a chorus from my idea", "Find chords for a hopeful mood", "Strengthen my verse lyrics", "Outline a complete song"]
    var body: some View {
        VStack(spacing: 10) {
            ForEach(suggestions, id: \.self) { suggestion in
                Button { choose(suggestion) } label: {
                    HStack { Text(suggestion); Spacer(); Image(systemName: "arrow.up.right") }
                        .font(.subheadline.weight(.regular)).frame(maxWidth: .infinity, minHeight: 44).padding(.horizontal, 14)
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
                }.buttonStyle(.plain)
            }
        }
    }
}
