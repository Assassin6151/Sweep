import SwiftUI

struct JunkCleanerView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let viewModel = model.junk
        VStack(spacing: 0) {
            ModuleHeader(module: .junk) {
                if viewModel.phase == .results {
                    Button {
                        viewModel.scan()
                    } label: {
                        Label("Erneut scannen", systemImage: "arrow.clockwise")
                    }
                    .keyboardShortcut("r", modifiers: .command)
                }
            }
            .padding(Theme.pagePadding)

            ZStack {
                switch viewModel.phase {
                case .idle:
                    HeroState(module: .junk,
                              title: "Bereit zum Aufräumen",
                              message: "Sweep sucht nach Caches, Protokollen, temporären Dateien, Xcode- und Homebrew-Resten. Du entscheidest danach, was weg darf.") {
                        Button("Junk suchen") { viewModel.scan() }
                            .buttonStyle(.prominent(SweepModule.junk.tint))
                            .keyboardShortcut("r", modifiers: .command)
                    }
                case .scanning:
                    ScanProgressView(tint: SweepModule.junk.tint,
                                     fraction: viewModel.progress.fraction,
                                     title: viewModel.progress.message,
                                     detail: viewModel.progress.currentPath,
                                     onCancel: viewModel.cancel)
                case .results, .cleaning:
                    JunkResultsView(viewModel: viewModel)
                }
            }
            .animation(Theme.spring, value: viewModel.phase)
        }
        .sheet(item: Binding(get: { viewModel.pendingPlan }, set: { viewModel.pendingPlan = $0 })) { plan in
            DeletionPreviewSheet(plan: plan, protection: viewModel.protection) { viewModel.clean($0) }
        }
    }
}

private struct JunkResultsView: View {
    @Environment(AppModel.self) private var model
    let viewModel: JunkCleanerViewModel

    var body: some View {
        VStack(spacing: 0) {
            summary
                .padding(.horizontal, Theme.pagePadding)
                .padding(.bottom, 16)

            if viewModel.results.isEmpty {
                HeroState(module: .junk, title: "Alles sauber", message: "Sweep hat keinen nennenswerten Junk gefunden.") { EmptyView() }
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        if viewModel.unreadableLocations > 0 {
                            UnreadableHint(count: viewModel.unreadableLocations) { model.selection = .permissions }
                        }
                        ForEach(viewModel.results) { result in
                            JunkCategoryCard(result: result, viewModel: viewModel)
                        }
                    }
                    .padding(.horizontal, Theme.pagePadding)
                    .padding(.bottom, 90)
                }
            }
        }
        .overlay(alignment: .bottom) {
            if let outcome = viewModel.lastOutcome {
                DeletionResultBanner(outcome: outcome,
                                     onShowLog: { model.selection = .activity },
                                     onDismiss: { withAnimation { viewModel.lastOutcome = nil } })
                    .padding(Theme.pagePadding)
            }
        }
        .animation(Theme.spring, value: viewModel.lastOutcome?.entry.id)
    }

    private var summary: some View {
        HStack(alignment: .bottom, spacing: 28) {
            BigNumber(bytes: viewModel.selectedSize, caption: "ausgewählt", tint: SweepModule.junk.tint)
            BigNumber(bytes: viewModel.totalFound, caption: "insgesamt gefunden", size: 26)
            Spacer()
            if viewModel.phase == .cleaning {
                ProgressView().controlSize(.small)
                Text("Wird entfernt …").foregroundStyle(.secondary)
            }
            Button {
                viewModel.prepareClean()
            } label: {
                Label("Aufräumen", systemImage: "sparkles")
            }
            .buttonStyle(.prominent(SweepModule.junk.tint))
            .disabled(viewModel.selection.isEmpty || viewModel.phase == .cleaning)
            .keyboardShortcut("k", modifiers: .command)
        }
        .animation(Theme.spring, value: viewModel.selectedSize)
    }
}

private struct JunkCategoryCard: View {
    let result: JunkCategoryResult
    let viewModel: JunkCleanerViewModel

    var body: some View {
        let isExpanded = viewModel.expanded.contains(result.id)
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                SelectionBox(state: viewModel.state(of: result), tint: SweepModule.junk.tint) {
                    withAnimation(Theme.spring) { viewModel.toggle(result) }
                }
                .disabled(result.items.isEmpty)
                Image(systemName: result.category.symbol)
                    .font(.title3)
                    .foregroundStyle(SweepModule.junk.tint)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(result.category.title).font(.headline)
                        if result.category.risk == .review {
                            Tag(text: "prüfen", color: .orange)
                        }
                        if result.category.deletionMode == .permanent {
                            Tag(text: "endgültig", color: .red)
                        }
                    }
                    Text(result.category.explanation)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if result.unreadableLocations > 0 {
                        Label("Teilweise nicht lesbar", systemImage: "lock")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                Spacer()
                if result.items.isEmpty {
                    Text("nicht geprüft")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    Text(ByteFormat.string(result.totalSize))
                        .font(.system(.title3, design: .rounded).weight(.semibold).monospacedDigit())
                }
                Button {
                    withAnimation(Theme.spring) { viewModel.toggleExpanded(result.id) }
                } label: {
                    Image(systemName: "chevron.right")
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(result.items.isEmpty)
            }
            .contentShape(Rectangle())
            .onTapGesture { withAnimation(Theme.spring) { viewModel.toggleExpanded(result.id) } }

            if isExpanded {
                Divider().padding(.vertical, 10)
                VStack(spacing: 6) {
                    ForEach(result.items.prefix(300)) { item in
                        JunkItemRow(item: item, isSelected: viewModel.selection.contains(item.id)) {
                            viewModel.toggle(item)
                        }
                    }
                    if result.items.count > 300 {
                        Text("… und \(result.items.count - 300) weitere")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .card()
    }
}

private struct JunkItemRow: View {
    let item: JunkItem
    let isSelected: Bool
    let toggle: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Toggle("", isOn: Binding(get: { isSelected }, set: { _ in toggle() }))
                .toggleStyle(.checkbox)
                .labelsHidden()
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name).lineLimit(1)
                Text(item.url.path)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Text(ByteFormat.string(item.size))
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([item.url])
            } label: {
                Image(systemName: "magnifyingglass")
            }
            .buttonStyle(.borderless)
            .help("Im Finder zeigen")
        }
        .padding(.leading, 40)
        .revealInFinderMenu(item.url)
    }
}

struct Tag: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }
}

/// Explains that some places could not be read and links to the permission guide.
struct UnreadableHint: View {
    let count: Int
    let action: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock.trianglebadge.exclamationmark")
                .foregroundStyle(.orange)
            Text("\(counted(count, "Bereich konnte", "Bereiche konnten")) nicht gelesen werden. Mit Festplattenvollzugriff findet Sweep mehr.")
                .font(.callout)
            Spacer()
            Button("Mehr erfahren", action: action)
        }
        .padding(12)
        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
    }
}
