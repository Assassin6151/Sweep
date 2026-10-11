import SwiftUI

struct SidebarView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        List(selection: $model.selection) {
            ForEach(SidebarSection.allCases) { section in
                Section(section.title) {
                    ForEach(section.modules) { module in
                        SidebarRow(module: module, badge: badge(for: module))
                            .tag(module)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            AccessStatusPill()
                .padding(12)
        }
    }

    private func badge(for module: SweepModule) -> String? {
        nil
    }
}

private struct SidebarRow: View {
    let module: SweepModule
    let badge: String?

    var body: some View {
        HStack(spacing: 10) {
            ModuleIcon(module: module, size: 22)
            Text(module.title)
                .lineLimit(1)
            Spacer(minLength: 4)
            if let badge {
                Text(badge)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            }
        }
        .padding(.vertical, 2)
    }
}

/// Small permanent hint at the bottom of the sidebar showing whether Full Disk Access is active.
private struct AccessStatusPill: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let granted = model.permissions.hasFullDiskAccess
        Button {
            model.selection = .permissions
        } label: {
            HStack(spacing: 8) {
                Image(systemName: granted ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                    .foregroundStyle(granted ? .green : .orange)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Festplattenvollzugriff")
                        .font(.caption.weight(.semibold))
                    Text(granted ? "Aktiv" : "Nicht erteilt – mehr erfahren")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .help("Zeigt, warum Sweep Festplattenvollzugriff braucht")
    }
}
