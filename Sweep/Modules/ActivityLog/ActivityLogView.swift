import SwiftUI

struct ActivityLogView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var viewModel = model.activity
        VStack(spacing: 0) {
            ModuleHeader(module: .activity) {
                if !viewModel.log.entries.isEmpty {
                    Button("Protokoll leeren", role: .destructive) { viewModel.confirmClear = true }
                }
            }
            .padding(Theme.pagePadding)

            if viewModel.log.entries.isEmpty {
                HeroState(module: .activity, title: "Noch keine Aktivität",
                          message: "Sobald Sweep etwas entfernt, siehst du hier genau, was wann wohin verschoben wurde – und kannst es aus dem Papierkorb zurückholen.") { EmptyView() }
            } else {
                HStack(alignment: .bottom, spacing: 28) {
                    BigNumber(bytes: viewModel.log.totalFreedBytes, caption: "insgesamt entfernt", tint: SweepModule.activity.tint)
                    BigNumber(value: "\(viewModel.log.entries.count)", caption: "Aktionen", size: 26)
                    Spacer()
                    Picker("Modul", selection: $viewModel.filter) {
                        Text("Alle Module").tag(SweepModule?.none)
                        ForEach(viewModel.modulesInLog) { module in
                            Text(module.title).tag(SweepModule?.some(module))
                        }
                    }
                    .frame(width: 200)
                    TextField("Suchen", text: $viewModel.searchText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 180)
                }
                .padding(.horizontal, Theme.pagePadding)
                .padding(.bottom, 16)

                List {
                    ForEach(viewModel.groupedEntries, id: \.day) { group in
                        Section(group.day.formatted(date: .complete, time: .omitted)) {
                            ForEach(group.entries) { entry in
                                ActivityEntryRow(entry: entry, viewModel: viewModel)
                            }
                        }
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
            }
        }
        .confirmationDialog("Protokoll wirklich leeren?", isPresented: $viewModel.confirmClear) {
            Button("Leeren", role: .destructive) { viewModel.clear() }
        } message: {
            Text("Die Einträge werden entfernt. Dateien im Papierkorb bleiben dort, lassen sich aber nicht mehr über Sweep wiederherstellen.")
        }
        .alert("Wiederherstellen nicht möglich", isPresented: Binding(get: { viewModel.errorMessage != nil }, set: { if !$0 { viewModel.errorMessage = nil } })) {
            Button("OK") {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }
}

private struct ActivityEntryRow: View {
    let entry: ActivityEntry
    let viewModel: ActivityLogViewModel

    var body: some View {
        let isExpanded = viewModel.expanded.contains(entry.id)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                ModuleIcon(module: entry.module, size: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.title).font(.headline)
                    HStack(spacing: 6) {
                        Text(entry.date.formatted(date: .omitted, time: .shortened))
                        Text("·")
                        Text(entry.action.title)
                        Text("·")
                        Text("\(entry.succeededCount) Einträge")
                        if entry.problemCount > 0 {
                            Tag(text: "\(entry.problemCount) Probleme", color: .orange)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                Text(ByteFormat.string(entry.freedBytes))
                    .font(.system(.body, design: .rounded).weight(.semibold).monospacedDigit())
                Image(systemName: "chevron.right")
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
            .onTapGesture { withAnimation(Theme.spring) { viewModel.toggle(entry) } }

            if isExpanded {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(entry.items) { item in
                        ActivityItemRow(item: item, canRestore: viewModel.canRestore(item)) {
                            viewModel.restore(item, in: entry)
                        }
                    }
                }
                .padding(.leading, 42)
                .transition(.opacity)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct ActivityItemRow: View {
    let item: ActivityItem
    let canRestore: Bool
    let restore: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: symbol)
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.path)
                    .font(.caption.monospaced())
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                if let message = item.message {
                    Text(message).font(.caption).foregroundStyle(color)
                }
            }
            Spacer()
            Text(ByteFormat.string(item.size))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            if canRestore {
                Button("Wiederherstellen", action: restore)
                    .controlSize(.small)
            }
        }
    }

    private var symbol: String {
        switch item.status {
        case .done: item.mode == .permanent ? "xmark.bin" : "trash"
        case .failed: "exclamationmark.triangle"
        case .blocked: "lock"
        case .restored: "arrow.uturn.backward.circle"
        }
    }

    private var color: Color {
        switch item.status {
        case .done: .secondary
        case .failed: .orange
        case .blocked: .orange
        case .restored: .green
        }
    }
}
