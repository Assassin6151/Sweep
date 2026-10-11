import SwiftUI

/// Shown before every deletion: lists every path with its size and asks for explicit confirmation.
struct DeletionPreviewSheet: View {
    let plan: DeletionPlan
    let protection: ProtectedPaths
    let onConfirm: (DeletionPlan) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var acknowledgedPermanent = false

    private var checked: [(candidate: DeletionCandidate, verdict: ProtectedPaths.Verdict)] {
        plan.candidates.map { ($0, protection.verdict(for: $0.url)) }
    }

    private var allowedCandidates: [DeletionCandidate] {
        checked.filter { $0.verdict.isAllowed }.map(\.candidate)
    }

    var body: some View {
        let allowed = allowedCandidates
        let blockedCount = plan.candidates.count - allowed.count
        let allowedSize = allowed.reduce(Int64(0)) { $0 + $1.size }
        let permanent = allowed.filter { $0.mode == .permanent }

        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 14) {
                ModuleIcon(module: plan.module, size: 40)
                VStack(alignment: .leading, spacing: 4) {
                    Text(plan.title).font(.title3.weight(.semibold))
                    Text(plan.message).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                BigNumber(bytes: allowedSize, caption: counted(allowed.count, "Eintrag", "Einträge"), tint: plan.module.tint, size: 30)
            }
            .padding(20)

            Divider()

            List {
                ForEach(checked, id: \.candidate.id) { entry in
                    PreviewRow(candidate: entry.candidate, verdict: entry.verdict)
                }
            }
            .listStyle(.inset)
            .frame(minHeight: 240)

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                if blockedCount > 0 {
                    Label("\(counted(blockedCount, "geschützter Eintrag wird", "geschützte Einträge werden")) übersprungen.", systemImage: "lock.fill")
                        .foregroundStyle(.orange)
                }
                if !permanent.isEmpty {
                    Toggle(isOn: $acknowledgedPermanent) {
                        Text("Mir ist klar, dass \(counted(permanent.count, "Eintrag", "Einträge")) aus dem Papierkorb **endgültig** gelöscht \(permanent.count == 1 ? "wird" : "werden").")
                    }
                    .toggleStyle(.checkbox)
                } else {
                    Label("Alles wird in den Papierkorb gelegt und kann von dort wiederhergestellt werden.", systemImage: "arrow.uturn.backward.circle")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Spacer()
                    Button("Abbrechen", role: .cancel) { dismiss() }
                        .keyboardShortcut(.cancelAction)
                    Button(permanent.isEmpty ? plan.confirmTitle : "Bestätigen und löschen") {
                        var confirmed = plan
                        confirmed.candidates = allowed
                        dismiss()
                        onConfirm(confirmed)
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(allowed.isEmpty || (!permanent.isEmpty && !acknowledgedPermanent))
                }
                .controlSize(.large)
            }
            .padding(20)
        }
        .frame(width: 680, height: 560)
    }
}

private struct PreviewRow: View {
    let candidate: DeletionCandidate
    let verdict: ProtectedPaths.Verdict

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: candidate.url.path))
                .resizable()
                .frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(candidate.url.lastPathComponent).lineLimit(1)
                    if candidate.mode == .permanent {
                        Text("endgültig")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Color.red.opacity(0.15), in: Capsule())
                            .foregroundStyle(.red)
                    }
                }
                Text(candidate.url.path)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let reason = verdict.reason {
                    Label(reason, systemImage: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            Spacer()
            Text(ByteFormat.string(candidate.size))
                .font(.callout.monospacedDigit())
                .foregroundStyle(verdict.isAllowed ? .primary : .tertiary)
        }
        .opacity(verdict.isAllowed ? 1 : 0.6)
    }
}

/// Confirmation banner shown after a deletion finished.
struct DeletionResultBanner: View {
    let outcome: DeletionOutcome
    var onShowLog: () -> Void
    var onDismiss: () -> Void

    var body: some View {
        let problems = outcome.problemItems.count
        HStack(spacing: 12) {
            Image(systemName: problems == 0 ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .font(.title2)
                .foregroundStyle(problems == 0 ? .green : .orange)
                .symbolEffect(.bounce, value: outcome.entry.id)
            VStack(alignment: .leading, spacing: 2) {
                Text(outcome.entry.action == .emptiedTrash
                     ? "\(ByteFormat.string(outcome.freedBytes)) endgültig freigegeben"
                     : "\(ByteFormat.string(outcome.freedBytes)) in den Papierkorb gelegt")
                    .font(.headline)
                Text(problems == 0
                     ? "\(counted(outcome.removedItems.count, "Eintrag", "Einträge")) entfernt. Leere den Papierkorb, um den Platz endgültig freizugeben."
                     : "\(outcome.removedItems.count) entfernt, \(problems) konnten nicht entfernt werden – Details im Protokoll.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Protokoll", action: onShowLog)
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

/// Tri-state checkbox for category headers.
struct SelectionBox: View {
    enum State { case none, some, all }
    let state: State
    var tint: Color = .accentColor
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: state == .all ? "checkmark.square.fill" : state == .some ? "minus.square.fill" : "square")
                .font(.system(size: 16))
                .foregroundStyle(state == .none ? Color.secondary : tint)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
    }
}

extension View {
    func revealInFinderMenu(_ url: URL) -> some View {
        contextMenu {
            Button("Im Finder zeigen") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            Button("Pfad kopieren") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(url.path, forType: .string)
            }
        }
    }
}
