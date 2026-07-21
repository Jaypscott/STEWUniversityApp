import SwiftUI
import UIKit

struct AppShellView: View {
    @State private var destination: AppDestination
    @State private var drawerOpen = false
    @State private var selectedJamInstrument: JamInstrument?
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var earTrainingProgress: EarTrainingProgressStore
    @EnvironmentObject private var gameProgress: GameProgressStore
    @EnvironmentObject private var bandAuth: BandAuthSession
    @EnvironmentObject private var bandStore: BandStore
    @EnvironmentObject private var bandNotifications: BandNotificationStore

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        let initialDestination: AppDestination
        if arguments.contains("--preview-band") || arguments.contains("--ui-testing-band-demo") || arguments.contains("--ui-testing-band-empty") || arguments.contains("--ui-testing-band-signed-out") {
            initialDestination = .band
        } else if arguments.contains("--preview-jam") {
            initialDestination = .jam
        } else if arguments.contains("--preview-games") {
            initialDestination = .games
        } else {
            initialDestination = .songwriting
        }
        _destination = State(initialValue: initialDestination)
        _selectedJamInstrument = State(initialValue: nil)
    }

    var body: some View {
        Group {
            if usesRegularSidebar {
                regularLayout
            } else {
                compactLayout
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await earTrainingProgress.handleForeground() }
            gameProgress.reconcile()
            if let user = bandAuth.currentUser {
                Task {
                    await bandStore.load(userID: user.id, force: true)
                    await bandNotifications.load()
                    await BandPushManager.shared.registerCachedTokenIfAvailable()
                }
            }
        }
        .onOpenURL { handleURL($0) }
        .onReceive(NotificationCenter.default.publisher(for: .bandNotificationRoute)) { _ in
            destination = .band
        }
    }

    private var usesRegularSidebar: Bool {
        UIDevice.current.userInterfaceIdiom == .pad && horizontalSizeClass == .regular
    }

    private var compactLayout: some View {
        NavigationStack {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    content
                        .disabled(drawerOpen)

                    if drawerOpen {
                        Color.black.opacity(0.28)
                            .ignoresSafeArea()
                            .accessibilityHidden(true)
                            .onTapGesture { closeDrawer() }
                            .transition(.opacity)

                        DrawerView(selection: $destination) { closeDrawer() }
                            .frame(width: min(STEWTheme.drawerWidth, geometry.size.width * 0.82))
                            .transition(.move(edge: .leading))
                            .gesture(
                                DragGesture().onEnded { value in
                                    if value.translation.width < -50 { closeDrawer() }
                                }
                            )
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { openDrawer() } label: {
                        Image(systemName: "line.3.horizontal")
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Open navigation menu")
                }
                ToolbarItem(placement: .principal) {
                    Text(destination.rawValue)
                        .font(.headline.weight(.regular))
                        .accessibilityIdentifier("compact-screen-heading")
                }
            }
            .toolbar(drawerOpen ? .hidden : .visible, for: .navigationBar)
        }
    }

    private var regularLayout: some View {
        NavigationSplitView {
            List {
                ForEach(AppDestination.allCases) { item in
                    Button {
                        destination = item
                    } label: {
                        Label(item.rawValue, systemImage: item.symbol)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(
                        destination == item ? STEWTheme.gold.opacity(0.16) : Color.clear
                    )
                    .accessibilityAddTraits(destination == item ? .isSelected : [])
                    .accessibilityIdentifier("sidebar-\(item.id)")
                }
            }
            .navigationTitle("STEW")
            .navigationSplitViewColumnWidth(min: 240, ideal: 270, max: 300)
        } detail: {
            NavigationStack {
                content
                    .navigationTitle(destination.rawValue)
                    .navigationBarTitleDisplayMode(.inline)
            }
            .id(destination)
        }
        .navigationSplitViewStyle(.balanced)
        .accessibilityIdentifier("ipad-navigation-split-view")
    }

    @ViewBuilder private var content: some View {
        switch destination {
        case .songwriting: SongwritingView()
        case .jam: JamView(selectedInstrument: $selectedJamInstrument)
        case .band: BandView()
        case .earTraining: EarTrainingView()
        case .visualizer: VisualizerView()
        case .games: GamesView()
        }
    }

    private func openDrawer() { withAnimation(reduceMotion ? nil : .snappy) { drawerOpen = true } }
    private func closeDrawer() { withAnimation(reduceMotion ? nil : .snappy) { drawerOpen = false } }

    private func handleURL(_ url: URL) {
        let parts = url.pathComponents.filter { $0 != "/" }
        guard let inviteIndex = parts.firstIndex(of: "invite"), parts.indices.contains(inviteIndex + 1) else { return }
        destination = .band
        bandStore.pendingInvitationToken = parts[inviteIndex + 1]
    }
}

private struct DrawerView: View {
    @Binding var selection: AppDestination
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("STEW").font(.title2.weight(.medium)).foregroundStyle(STEWTheme.gold)
                Text("UNIVERSITY").font(.caption2.weight(.regular)).tracking(2).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 18).padding(.bottom, 24)

            ForEach(AppDestination.allCases) { item in
                Button {
                    selection = item
                    close()
                } label: {
                    Label(item.rawValue, systemImage: item.symbol)
                        .font(.body.weight(.regular))
                        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                        .padding(.horizontal, 14)
                        .background(selection == item ? STEWTheme.gold.opacity(0.16) : .clear, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == item ? .isSelected : [])
            }
            Spacer()
            Text("Create · Learn · Listen")
                .font(.footnote.weight(.light)).foregroundStyle(.secondary).padding(18)
        }
        .padding(.top, 22).padding(.horizontal, 10)
        .frame(maxHeight: .infinity)
        .background(.regularMaterial)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Navigation menu")
    }
}
