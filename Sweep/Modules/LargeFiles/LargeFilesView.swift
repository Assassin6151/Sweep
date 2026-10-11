import SwiftUI

struct LargeFilesView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var viewModel = model.largeFiles
        VStack(spacing: 0) {
            ModuleHeader(module: .largeFiles) {
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
                    HeroState(module: .largeFiles, title: "Platzfresser aufspüren",
                              message: "Sweep listet alle Dateien ab 50 MB in deinem Benutzerordner. Danach filterst du nach Größe, Alter und Art.") {
                        VStack(spacing: 12) {
                            Toggle("Auch ~/Library durchsuchen", isOn: $viewModel.includeLibrary)
                                .toggleStyle(.checkbox)
                            Button("Große Dateien suchen") { viewModel.scan() }
                                .buttonStyle(.prominent(SweepModule.largeFiles.tint))
                                .keyboardShortcut("r", modifiers: .command)
                        }
                    }
                case .scanning:
                    ScanProgressView(tint: SweepModule.largeFiles.tint, fraction: nil,
                                     title: viewModel.progress.message, detail: viewModel.progress.currentPath,
                                     onCancel: viewModel.cancel)
                case .results, .removing:
                    LargeFileResults(viewModel: viewModel)
                }
            }
            .animation(Theme.spring, value: viewModel.phase)
        }
        .sheet(item: $viewModel.pendingPlan) { plan in
            DeletionPreviewSheet(plan: plan, protection: viewModel.protection) { viewModel.execute($0) }
        }
    }
}

private struct LargeFileResults: View {
    @Environment(AppModel.self) private var model
    @Bindable var viewModel: LargeFilesViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .bottom, spacing: 28) {
                BigNumber(bytes: viewModel.visibleSize, caption: "\(counted(viewModel.visibleFiles.count, "Datei", "Dateien")) im Filter", tint: SweepModule.largeFiles.tint)
                if !viewModel.selection.isEmpty {
                    BigNumber(bytes: viewModel.selectedSize, caption: "\(viewModel.selection.count) ausgewählt", size: 26)
                        .transition(.opacity)
                }
                Spacer()
                Button {
                    viewModel.prepareRemoval()
                } label: {
                    Label("In den Papierkorb", systemImage: "trash")
                }
                .buttonStyle(.prominent(SweepModule.largeFiles.tint))
                .disabled(viewModel.selection.isEmpty || viewModel.phase == .removing)
                .keyboardShortcut("k", modifiers: .command)
            }
            .animation(Theme.spring, value: viewModel.selectedSize)

            filters

            KindChips(viewModel: viewModel)

            Table(viewModel.visibleFiles, selection: $viewModel.selection, sortOrder: $viewModel.sortOrder) {
                TableColumn("Name", value: \.name) { file in
                    HStack(spacing: 8) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: file.url.path))
                            .resizable()
                            .frame(width: 18, height: 18)
                        Text(file.name).lineLimit(1)
                    }
                    .revealInFinderMenu(file.url)
                }
                .width(min: 180, ideal: 260)
                TableColumn("Größe", value: \.size) { file in
                    Text(ByteFormat.string(file.size)).monospacedDigit()
                }
                .width(90)
                TableColumn("Zuletzt benutzt", value: \.lastUsedSortKey) { file in
                    Text(file.lastUsed?.formatted(date: .abbreviated, time: .omitted) ?? "–")
                        .foregroundStyle(.secondary)
                }
                .width(120)
                TableColumn("Ort", value: \.folder) { file in
                    Text(file.folder.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                        .font(.callout.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .contextMenu(forSelectionType: String.self) { ids in
                Button("Im Finder zeigen") {
                    NSWorkspace.shared.activateFileViewerSelecting(ids.map { URL(fileURLWithPath: $0) })
                }
                Button("In den Papierkorb legen …", role: .destructive) {
                    viewModel.selection = ids
                    viewModel.prepareRemoval()
                }
            } primaryAction: { ids in
                NSWorkspace.shared.activateFileViewerSelecting(ids.map { URL(fileURLWithPath: $0) })
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        }
        .padding([.horizontal, .bottom], Theme.pagePadding)
        .overlay(alignment: .bottom) {
            if let outcome = viewModel.lastOutcome {
                DeletionResultBanner(outcome: outcome, onShowLog: { model.selection = .activity },
                                     onDismiss: { withAnimation { viewModel.lastOutcome = nil } })
                    .padding(Theme.pagePadding)
            }
        }
    }

    private var filters: some View {
        HStack(spacing: 16) {
            Picker("Mindestgröße", selection: $viewModel.minimumSize.animation(Theme.spring)) {
                Text("50 MB").tag(Int64(50 * 1_048_576))
                Text("100 MB").tag(Int64(100 * 1_048_576))
                Text("250 MB").tag(Int64(250 * 1_048_576))
                Text("500 MB").tag(Int64(500 * 1_048_576))
                Text("1 GB").tag(Int64(1_073_741_824))
                Text("5 GB").tag(Int64(5 * 1_073_741_824))
            }
            .frame(width: 200)
            Picker("Nicht benutzt seit", selection: $viewModel.olderThanDays.animation(Theme.spring)) {
                Text("egal").tag(0)
                Text("1 Monat").tag(30)
                Text("3 Monaten").tag(90)
                Text("6 Monaten").tag(180)
                Text("1 Jahr").tag(365)
                Text("2 Jahren").tag(730)
            }
            .frame(width: 250)
            Spacer()
        }
    }
}

private struct KindChips: View {
    @Bindable var viewModel: LargeFilesViewModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(title: "Alle", symbol: "square.grid.2x2", color: SweepModule.largeFiles.tint, detail: nil, isOn: viewModel.kindFilter == nil) {
                    viewModel.kindFilter = nil
                }
                ForEach(viewModel.kindTotals, id: \.kind) { total in
                    chip(title: total.kind.title, symbol: total.kind.symbol, color: total.kind.color,
                         detail: ByteFormat.string(total.size), isOn: viewModel.kindFilter == total.kind) {
                        viewModel.kindFilter = viewModel.kindFilter == total.kind ? nil : total.kind
                    }
                }
            }
        }
    }

    private func chip(title: String, symbol: String, color: Color, detail: String?, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(Theme.spring) { action() }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: symbol).foregroundStyle(isOn ? .white : color)
                Text(title)
                if let detail {
                    Text(detail).monospacedDigit().foregroundStyle(isOn ? .white.opacity(0.8) : .secondary)
                }
            }
            .font(.callout)
            .foregroundStyle(isOn ? .white : .primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isOn ? AnyShapeStyle(color.gradient) : AnyShapeStyle(.quaternary.opacity(0.6)), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

private extension LargeFile {
    var lastUsedSortKey: Date { lastUsed ?? .distantPast }
}
