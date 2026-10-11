import SwiftUI

struct SpaceMapView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var viewModel = model.spaceMap
        VStack(spacing: 0) {
            ModuleHeader(module: .spaceMap) {
                if viewModel.phase == .results {
                    targetMenu(viewModel)
                }
            }
            .padding(Theme.pagePadding)

            ZStack {
                switch viewModel.phase {
                case .idle:
                    idle(viewModel)
                case .scanning:
                    ScanProgressView(
                        tint: SweepModule.spaceMap.tint, fraction: nil,
                        title: "\(ByteFormat.string(viewModel.progress.bytes)) erfasst · \(viewModel.progress.files.formatted()) Dateien",
                        detail: viewModel.progress.currentPath, onCancel: viewModel.cancel)
                case .results:
                    SpaceMapResults(viewModel: viewModel)
                }
            }
            .animation(Theme.spring, value: viewModel.phase)
        }
        .sheet(item: $viewModel.pendingPlan) { plan in
            DeletionPreviewSheet(plan: plan, protection: viewModel.protection) { viewModel.execute($0) }
        }
    }

    private func idle(_ viewModel: SpaceMapViewModel) -> some View {
        HeroState(module: .spaceMap, title: "Wohin ist dein Speicherplatz verschwunden?",
                  message: "Sweep vermisst einen Ordner und zeigt ihn als Karte: Je größer die Fläche, desto mehr Platz belegt der Eintrag.") {
            VStack(spacing: 16) {
                if let volume = viewModel.volume {
                    VolumeBar(volume: volume).frame(width: 420)
                }
                HStack {
                    Button("Benutzerordner analysieren") { viewModel.scanHome() }
                        .buttonStyle(.prominent(SweepModule.spaceMap.tint))
                        .keyboardShortcut("r", modifiers: .command)
                    Button("Ordner wählen …") { viewModel.chooseFolder() }
                        .controlSize(.large)
                }
            }
        }
    }

    private func targetMenu(_ viewModel: SpaceMapViewModel) -> some View {
        Menu {
            Button("Benutzerordner") { viewModel.scanHome() }
            Button("Startvolume") { viewModel.scanStartupVolume() }
            Button("Ordner wählen …") { viewModel.chooseFolder() }
            Divider()
            Button("Erneut analysieren") { viewModel.rescan() }
        } label: {
            Label("Analysieren", systemImage: "scope")
        }
        .fixedSize()
    }
}

struct VolumeBar: View {
    let volume: VolumeInfo
    var highlight: Int64 = 0
    var highlightTitle = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(volume.name, systemImage: "internaldrive").font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(ByteFormat.string(volume.available)) von \(ByteFormat.string(volume.total)) frei")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            GeometryReader { geometry in
                let width = geometry.size.width
                let highlightFraction = volume.total > 0 ? min(Double(highlight) / Double(volume.total), volume.usedFraction) : 0
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule().fill(SweepModule.spaceMap.tint.gradient)
                        .frame(width: width * volume.usedFraction)
                    if highlight > 0 {
                        Capsule().fill(SweepModule.junk.tint.gradient)
                            .frame(width: max(6, width * highlightFraction))
                            .offset(x: width * (volume.usedFraction - highlightFraction))
                    }
                }
            }
            .frame(height: 10)
            if highlight > 0 {
                HStack(spacing: 6) {
                    Circle().fill(SweepModule.junk.tint).frame(width: 7, height: 7)
                    Text("\(highlightTitle): \(ByteFormat.string(highlight))").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .animation(Theme.spring, value: highlight)
    }
}

private struct SpaceMapResults: View {
    @Environment(AppModel.self) private var model
    @Bindable var viewModel: SpaceMapViewModel

    var body: some View {
        if let current = viewModel.current {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 8) {
                        Breadcrumb(viewModel: viewModel)
                        BigNumber(bytes: current.size, caption: "\(current.fileCount.formatted()) Dateien", tint: SweepModule.spaceMap.tint, size: 36)
                    }
                    Spacer()
                    if let volume = viewModel.volume {
                        VolumeBar(volume: volume).frame(width: 300)
                    }
                }
                if viewModel.unreadableCount > 0 && !model.permissions.hasFullDiskAccess {
                    UnreadableHint(count: viewModel.unreadableCount) { model.selection = .permissions }
                }

                HStack(spacing: 14) {
                    TreemapView(node: current, hovered: $viewModel.hovered,
                                onOpen: { node in withAnimation(Theme.spring) { viewModel.open(node) } },
                                onTrash: viewModel.prepareTrash)
                        .id(current.id)
                        .transition(.scale(scale: 0.96).combined(with: .opacity))
                        .frame(minWidth: 360, maxWidth: .infinity, maxHeight: .infinity)

                    ChildList(node: current, viewModel: viewModel)
                        .frame(width: 290)
                }
                .animation(Theme.spring, value: current.id)

                HoverInfo(node: viewModel.hovered, parentSize: current.size)
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
    }
}

private struct Breadcrumb: View {
    let viewModel: SpaceMapViewModel

    var body: some View {
        HStack(spacing: 4) {
            Button {
                withAnimation(Theme.spring) { viewModel.goUp() }
            } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(viewModel.path.isEmpty)
            .keyboardShortcut(.upArrow, modifiers: .command)

            ForEach(viewModel.breadcrumb, id: \.depth) { item in
                if item.depth > 0 {
                    Image(systemName: "chevron.compact.right").foregroundStyle(.tertiary)
                }
                Button(item.name) {
                    withAnimation(Theme.spring) { viewModel.go(toDepth: item.depth) }
                }
                .buttonStyle(.plain)
                .foregroundStyle(item.depth == viewModel.path.count ? .primary : .secondary)
                .fontWeight(item.depth == viewModel.path.count ? .semibold : .regular)
            }
        }
        .lineLimit(1)
    }
}

private struct ChildList: View {
    let node: DiskNode
    let viewModel: SpaceMapViewModel

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 4) {
                ForEach(Array(node.children.enumerated()), id: \.element.id) { index, child in
                    let share = node.size > 0 ? Double(child.size) / Double(node.size) : 0
                    Button {
                        withAnimation(Theme.spring) { viewModel.open(child) }
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(child.name).lineLimit(1).truncationMode(.middle)
                                Spacer()
                                Text(ByteFormat.string(child.size))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            GeometryReader { geometry in
                                Capsule()
                                    .fill(TreemapPalette.color(for: child, index: index).gradient)
                                    .frame(width: max(3, geometry.size.width * share))
                            }
                            .frame(height: 5)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(viewModel.hovered?.id == child.id ? Color.primary.opacity(0.06) : .clear,
                                    in: RoundedRectangle(cornerRadius: 8))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .onHover { inside in if inside { viewModel.hovered = child } }
                    .contextMenu {
                        if child.isRealItem {
                            Button("Im Finder zeigen") { NSWorkspace.shared.activateFileViewerSelecting([child.url]) }
                            Button("In den Papierkorb legen …", role: .destructive) { viewModel.prepareTrash(child) }
                        }
                    }
                }
            }
        }
        .card(padding: 6)
    }
}

private struct HoverInfo: View {
    let node: DiskNode?
    let parentSize: Int64

    var body: some View {
        HStack(spacing: 8) {
            if let node {
                Image(systemName: node.kind == .folder ? "folder" : "doc")
                    .foregroundStyle(.secondary)
                Text(node.kind.isAggregate ? node.name : node.url.path)
                    .font(.callout.monospaced())
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Text(ByteFormat.string(node.size)).font(.callout.monospacedDigit().weight(.semibold))
                if parentSize > 0 {
                    Text((Double(node.size) / Double(parentSize)).formatted(.percent.precision(.fractionLength(1))))
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Fahre über eine Fläche für Details · Klick öffnet Ordner · Rechtsklick für Aktionen")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .frame(height: 22)
    }
}

private extension DiskNode.Kind {
    var isAggregate: Bool {
        if case .other = self { return true }
        return false
    }
}
