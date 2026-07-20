import SwiftUI

enum STEWTheme {
    static let gold = Color(red: 0.90, green: 0.66, blue: 0.09)
    static let ink = Color(red: 0.08, green: 0.10, blue: 0.12)
    static let drawerWidth: CGFloat = 292
    static let readingWidth: CGFloat = 840
    static let contentWidth: CGFloat = 1_200
    static let formWidth: CGFloat = 680
}

struct SurfaceModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(18)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20))
            .overlay {
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color(.separator).opacity(0.45), lineWidth: 0.5)
            }
    }
}

extension View {
    func stewSurface() -> some View { modifier(SurfaceModifier()) }

    func adaptiveContentWidth(
        _ maxWidth: CGFloat = STEWTheme.contentWidth,
        alignment: Alignment = .center
    ) -> some View {
        frame(maxWidth: maxWidth, alignment: alignment)
            .frame(maxWidth: .infinity, alignment: alignment)
    }

    func adaptiveFormWidth() -> some View {
        frame(maxWidth: STEWTheme.formWidth)
            .frame(maxWidth: .infinity)
    }
}

extension String {
    var stewPlainText: String {
        let attributedContent = (try? AttributedString(
            markdown: self,
            options: .init(interpretedSyntax: .full)
        )) ?? AttributedString(self)
        return String(attributedContent.characters)
    }
}

struct TypewriterText: View {
    let text: String
    let animates: Bool
    let onProgress: () -> Void
    let onComplete: () -> Void

    @State private var visibleCharacters = 0

    init(
        text: String,
        animates: Bool,
        onProgress: @escaping () -> Void = {},
        onComplete: @escaping () -> Void = {}
    ) {
        self.text = text
        self.animates = animates
        self.onProgress = onProgress
        self.onComplete = onComplete
    }

    private var characters: [Character] {
        Array(text)
    }

    private var visibleText: String {
        animates ? String(characters.prefix(visibleCharacters)) : text
    }

    var body: some View {
        Text(visibleText)
            .task(id: animates) {
                let allCharacters = characters
                guard animates, !allCharacters.isEmpty else {
                    visibleCharacters = allCharacters.count
                    onComplete()
                    return
                }

                visibleCharacters = 0
                let chunkSize = max(1, (allCharacters.count + 219) / 220)
                var updateCount = 0

                while visibleCharacters < allCharacters.count {
                    do {
                        try await Task.sleep(for: .milliseconds(20))
                    } catch {
                        return
                    }

                    visibleCharacters = min(visibleCharacters + chunkSize, allCharacters.count)
                    updateCount += 1
                    if updateCount.isMultiple(of: 4) || visibleCharacters == allCharacters.count {
                        onProgress()
                    }
                }

                onComplete()
            }
    }
}
