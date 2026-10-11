import SwiftUI

struct DuplicatesView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var viewModel = model.duplicates
        VStack(spacing: 0) {
            ModuleHeader(module: .duplicates) {
                if viewModel.phase == .results {
                    Button {
                        viewModel.newScan()
                    } label: {
                        Label("Neue Suche", systemImage: "arrow.clockwise")
                    }
                }
            }
            .padding(Theme.pagePadding)

            ZStack {
                switch viewModel.phase {
                case .idle:
                    DuplicateSetup(viewModel: viewModel)
                case .scanning:
                    ScanProgressView(tint: SweepModule.duplicates.tint, fraction: viewModel.progress.fraction,
                                     title: viewModel.progress.message, detail: viewModel.progress.currentPath,
                                     onCancel: viewModel.cancel)
                case .results, .removing:
                    DuplicateResults(viewModel: viewModel)
                }
            }
            .animation(Theme.spring, value: viewModel.phase)
        }
        .sheet(item: $viewModel.pendingPlan) { plan in
            DeletionPreviewSheet(plan: plan, protection: viewModel.protection) { viewModel.execute($0) }
        }
        .alert(viewModel.hint ?? "", isPresented: Binding(get: { viewModel.hint != nil }, set: { if !$0 { viewModel.hint = nil } })) {
            Button("OK") {}
        }
    }
}

private struct DuplicateSetup: View {
    @Bindable var viewModel: DuplicatesViewModel

    var body: some View {
        HeroState(module: .duplicates, title: "Doppelte Dateien finden",
                  message: "Sweep vergleicht die Inhalte der Dateien, nicht nur die Namen. Von jeder Gruppe bleibt immer mindestens eine Kopie erhalten.") {
            VStack(spacing: 14) {
                FolderChips(roots: viewModel.roots, onRemove: viewModel.remove, onAdd: viewModel.addFolders)
                    .frame(maxWidth: 560)
                Picker("Mindestgröße", selection: $viewModel.minimumSize) {
                    Text("100 KB").tag(Int64(102_400))
                    Text("1 MB").tag(Int64(1_048_576))
                    Text("10 MB").tag(Int64(10_485_760))
                    Text("100 MB").tag(Int64(104_857_600))
                }
                .frame(width: 220)
                Button("Duplikate suchen") { viewModel.scan() }
                    .buttonStyle(.prominent(SweepModule.duplicates.tint))
                    .disabled(viewModel.roots.isEmpty)
                    .keyboardShortcut("r", modifiers: .command)
            }
        }
    }
}

/// Editable list of folders shown as removable chips.
struct FolderChips: View {
    let roots: [URL]
    let onRemove: (URL) -> Void
    let onAdd: () -> Void

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(roots, id: \.self) { root in
                HStack(spacing: 4) {
                    Image(systemName: "folder.fill").foregroundStyle(.secondary)
                    Text(root.lastPathComponent)
                    Button {
                        withAnimation(Theme.spring) { onRemove(root) }
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.quaternary.opacity(0.7), in: Capsule())
                .help(root.path)
            }
            Button(action: onAdd) {
                Label("Ordner", systemImage: "plus")
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().strokeBorder(.separator))
            }
            .buttonStyle(.plain)
        }
    }
}

/// Simple wrapping layout for chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        let height = rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(0, rows.count - 1))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX + (bounds.width - row.width) / 2
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row { var indices: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if !rows[rows.count - 1].indices.isEmpty && rows[rows.count - 1].width + spacing + size.width > width {
                rows.append(Row())
            }
            var row = rows[rows.count - 1]
            row.width += (row.indices.isEmpty ? 0 : spacing) + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
            rows[rows.count - 1] = row
        }
        return rows
    }
}

private struct DuplicateResults: View {
    @Environment(AppModel.self) private var model
    @Bindable var viewModel: DuplicatesViewModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .bottom, spacing: 28) {
                BigNumber(bytes: viewModel.selectedSize, caption: "ausgewählt", tint: SweepModule.duplicates.tint)
                BigNumber(bytes: viewModel.totalWasted, caption: counted(viewModel.duplicateFileCount, "überzählige Kopie", "überzählige Kopien"), size: 26)
                Spacer()
                Picker("Auswahl", selection: $viewModel.keepRule) {
                    ForEach(KeepRule.allCases) { Text($0.title).tag($0) }
                }
                .frame(width: 240)
                Button {
                    viewModel.prepareRemoval()
                } label: {
                    Label("Kopien entfernen", systemImage: "trash")
                }
                .buttonStyle(.prominent(SweepModule.duplicates.tint))
                .disabled(viewModel.selection.isEmpty || viewModel.phase == .removing)
                .keyboardShortcut("k", modifiers: .command)
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.bottom, 16)
            .animation(Theme.spring, value: viewModel.selectedSize)

            if viewModel.groups.isEmpty {
                HeroState(module: .duplicates, title: "Keine Duplikate gefunden",
                          message: "In den gewählten Ordnern gibt es keine identischen Dateien über der Mindestgröße.") { EmptyView() }
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(viewModel.groups) { group in
                            DuplicateGroupCard(group: group, viewModel: viewModel)
                        }
                    }
                    .padding(.horizontal, Theme.pagePadding)
                    .padding(.bottom, 90)
                }
            }
        }
        .overlay(alignment: .bottom) {
            if let outcome = viewModel.lastOutcome {
                DeletionResultBanner(outcome: outcome, onShowLog: { model.selection = .activity },
                                     onDismiss: { withAnimation { viewModel.lastOutcome = nil } })
                    .padding(Theme.pagePadding)
            }
        }
    }
}

private struct DuplicateGroupCard: View {
    let group: DuplicateGroup
    let viewModel: DuplicatesViewModel

    var body: some View {
        let isExpanded = viewModel.expanded.contains(group.id)
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: group.files[0].url.path))
                    .resizable()
                    .frame(width: 32, height: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(group.name).font(.headline).lineLimit(1)
                    Text("\(group.files.count) Kopien à \(ByteFormat.string(group.size))")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(ByteFormat.string(group.wastedBytes))
                    .font(.system(.title3, design: .rounded).weight(.semibold).monospacedDigit())
                Image(systemName: "chevron.right")
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
            .onTapGesture { withAnimation(Theme.spring) { viewModel.toggleExpanded(group) } }

            if isExpanded {
                Divider().padding(.vertical, 10)
                VStack(spacing: 6) {
                    ForEach(group.files) { file in
                        let selected = viewModel.selection.contains(file.id)
                        HStack(spacing: 10) {
                            Toggle("", isOn: Binding(get: { selected }, set: { _ in viewModel.toggle(file, in: group) }))
                                .toggleStyle(.checkbox)
                                .labelsHidden()
                            VStack(alignment: .leading, spacing: 1) {
                                Text(file.url.path)
                                    .font(.callout.monospaced())
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                if let modified = file.modified {
                                    Text("Geändert \(modified.formatted(date: .abbreviated, time: .shortened))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if !selected {
                                Tag(text: "bleibt", color: .green)
                            }
                            Button {
                                NSWorkspace.shared.activateFileViewerSelecting([file.url])
                            } label: {
                                Image(systemName: "magnifyingglass")
                            }
                            .buttonStyle(.borderless)
                            .help("Im Finder zeigen")
                        }
                        .revealInFinderMenu(file.url)
                    }
                }
                .transition(.opacity)
            }
        }
        .card()
    }
}
