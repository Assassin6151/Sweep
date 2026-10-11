import SwiftUI

struct UninstallerView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var viewModel = model.uninstaller
        VStack(spacing: 0) {
            ModuleHeader(module: .uninstaller) {
                Button {
                    viewModel.reload()
                } label: {
                    Label("Neu laden", systemImage: "arrow.clockwise")
                }
                .disabled(viewModel.isLoading)
            }
            .padding(Theme.pagePadding)

            if viewModel.isLoading && viewModel.apps.isEmpty {
                ScanProgressView(tint: SweepModule.uninstaller.tint, fraction: nil,
                                 title: "Apps werden gesucht …", detail: "/Applications")
            } else {
                HSplitView {
                    AppListPane(viewModel: viewModel)
                        .frame(minWidth: 300, idealWidth: 340, maxWidth: 440)
                    Group {
                        if let app = viewModel.selectedApp {
                            AppDetailPane(app: app, viewModel: viewModel)
                                .id(app.id)
                        } else {
                            HeroState(module: .uninstaller, title: "Wähle eine App",
                                      message: "Links siehst du alle installierten Apps. Wähle eine aus, um zu sehen, welche Dateien zu ihr gehören.") { EmptyView() }
                        }
                    }
                    .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .task { viewModel.loadIfNeeded() }
        .sheet(item: $viewModel.pendingPlan) { plan in
            DeletionPreviewSheet(plan: plan, protection: viewModel.protection) { viewModel.execute($0) }
        }
        .alert("\(viewModel.runningAppToQuit?.name ?? "Die App") läuft noch",
               isPresented: Binding(get: { viewModel.runningAppToQuit != nil }, set: { if !$0 { viewModel.cancelQuit() } })) {
            Button("Beenden und fortfahren") { viewModel.quitRunningAppAndContinue() }
            Button("Abbrechen", role: .cancel) { viewModel.cancelQuit() }
        } message: {
            Text("Damit keine Dateien in Benutzung sind, sollte die App vorher beendet werden. Ungesicherte Änderungen fragt die App selbst ab.")
        }
    }
}

private struct AppListPane: View {
    @Bindable var viewModel: UninstallerViewModel

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                TextField("Apps durchsuchen", text: $viewModel.searchText)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Picker("Sortieren", selection: $viewModel.sortOrder) {
                        ForEach(UninstallerViewModel.SortOrder.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .frame(width: 150)
                    Spacer()
                    Toggle(isOn: $viewModel.onlyUnused.animation(Theme.spring)) {
                        Text("Ungenutzt (\(viewModel.unusedCount))")
                    }
                    .toggleStyle(.button)
                    .help("Apps, die seit \(viewModel.unusedDays) Tagen nicht geöffnet wurden")
                }
                if viewModel.onlyUnused {
                    Picker("Nicht benutzt seit", selection: $viewModel.unusedDays) {
                        Text("30 Tagen").tag(30)
                        Text("90 Tagen").tag(90)
                        Text("180 Tagen").tag(180)
                        Text("einem Jahr").tag(365)
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(12)

            List(selection: $viewModel.selectedAppID) {
                ForEach(viewModel.visibleApps) { app in
                    AppRow(app: app, isUnused: app.isUnused(days: viewModel.unusedDays))
                        .tag(app.id)
                }
            }
            .listStyle(.inset)
            .overlay {
                if viewModel.visibleApps.isEmpty {
                    Text(viewModel.onlyUnused ? "Keine lange ungenutzten Apps 🎉" : "Keine Apps gefunden")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct AppRow: View {
    let app: InstalledApp
    let isUnused: Bool

    var body: some View {
        HStack(spacing: 10) {
            AppIconView(url: app.url, size: 32)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(app.name).lineLimit(1)
                    if isUnused {
                        Image(systemName: "moon.zzz.fill")
                            .font(.caption2)
                            .foregroundStyle(SweepModule.uninstaller.tint)
                            .help("Lange nicht benutzt")
                    }
                }
                Text(app.lastUsedDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if let size = app.size {
                Text(ByteFormat.string(size))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            } else {
                ProgressView().controlSize(.mini)
            }
        }
        .padding(.vertical, 2)
        .revealInFinderMenu(app.url)
    }
}

struct AppIconView: View {
    let url: URL
    var size: CGFloat = 32

    var body: some View {
        Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
    }
}

private struct AppDetailPane: View {
    let app: InstalledApp
    @Bindable var viewModel: UninstallerViewModel
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .center, spacing: 16) {
                    AppIconView(url: app.url, size: 72)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(app.name).font(.title.weight(.semibold))
                        Text([app.version.map { "Version \($0)" }, app.bundleID, app.isFromAppStore ? "App Store" : nil]
                            .compactMap { $0 }.joined(separator: " · "))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                        Text(app.lastUsedDescription)
                            .font(.callout)
                            .foregroundStyle(app.isUnused(days: viewModel.unusedDays) ? SweepModule.uninstaller.tint : .secondary)
                    }
                }

                HStack(spacing: 32) {
                    BigNumber(bytes: app.size ?? 0, caption: "App", size: 30)
                    BigNumber(bytes: viewModel.leftoverSize, caption: "zugehörige Dateien", tint: SweepModule.uninstaller.tint, size: 30)
                    BigNumber(bytes: (app.size ?? 0) + viewModel.selectedLeftoverSize, caption: "wird beim Deinstallieren frei", size: 30)
                }

                HStack(spacing: 10) {
                    Button {
                        viewModel.prepareUninstall()
                    } label: {
                        Label("Deinstallieren", systemImage: "trash")
                    }
                    .buttonStyle(.prominent(SweepModule.uninstaller.tint))
                    .disabled(viewModel.isSearchingLeftovers)

                    Button {
                        viewModel.prepareReset()
                    } label: {
                        Label("Zurücksetzen", systemImage: "arrow.counterclockwise")
                    }
                    .controlSize(.large)
                    .disabled(viewModel.selectedLeftovers.isEmpty || viewModel.isSearchingLeftovers)
                    .help("Einstellungen und Daten entfernen, App behalten")
                }

                if let outcome = viewModel.lastOutcome {
                    DeletionResultBanner(outcome: outcome, onShowLog: { model.selection = .activity },
                                         onDismiss: { withAnimation { viewModel.lastOutcome = nil } })
                }

                if viewModel.skippedLocations > 0 {
                    UnreadableHint(count: viewModel.skippedLocations) { model.selection = .permissions }
                }

                leftoverSection
            }
            .padding(Theme.pagePadding)
        }
        .animation(Theme.spring, value: viewModel.leftovers)
    }

    @ViewBuilder
    private var leftoverSection: some View {
        if viewModel.isSearchingLeftovers {
            HStack {
                ProgressView().controlSize(.small)
                Text("Suche zugehörige Dateien …").foregroundStyle(.secondary)
            }
        } else if viewModel.leftovers.isEmpty {
            Label("Keine zugehörigen Dateien gefunden.", systemImage: "checkmark.circle")
                .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 14) {
                Text("Zugehörige Dateien").font(.headline)
                ForEach(viewModel.groupedLeftovers, id: \.kind) { group in
                    VStack(alignment: .leading, spacing: 6) {
                        Label(group.kind.title, systemImage: group.kind.symbol)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                        ForEach(group.items) { leftover in
                            LeftoverRow(leftover: leftover, isSelected: viewModel.selectedLeftovers.contains(leftover.id)) {
                                viewModel.toggle(leftover)
                            }
                        }
                    }
                }
            }
            .card()
        }
    }
}

private struct LeftoverRow: View {
    let leftover: Leftover
    let isSelected: Bool
    let toggle: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Toggle("", isOn: Binding(get: { isSelected }, set: { _ in toggle() }))
                .toggleStyle(.checkbox)
                .labelsHidden()
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(leftover.url.lastPathComponent).lineLimit(1)
                    if leftover.confidence == .medium {
                        Tag(text: "Name-Treffer", color: .orange)
                            .help("Nur über den App-Namen gefunden – bitte prüfen. Nicht vorausgewählt.")
                    }
                    if leftover.isSystemWide {
                        Tag(text: "systemweit", color: .secondary)
                    }
                }
                Text(leftover.url.deletingLastPathComponent().path)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Text(ByteFormat.string(leftover.size))
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .revealInFinderMenu(leftover.url)
    }
}
