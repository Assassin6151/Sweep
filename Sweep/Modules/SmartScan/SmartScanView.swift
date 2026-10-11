import SwiftUI

struct SmartScanView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let viewModel = model.smartScan
        ScrollView {
            VStack(spacing: 28) {
                hero(viewModel)
                if !model.permissions.hasFullDiskAccess {
                    AccessReminder { model.selection = .permissions }
                }
                HStack(alignment: .top, spacing: 14) {
                    ForEach(SmartScanViewModel.Part.allCases) { part in
                        PartCard(part: part, viewModel: viewModel) { model.selection = part.module }
                    }
                }
                if let volume = model.spaceMap.volume {
                    VolumeBar(volume: volume, highlight: viewModel.phase == .done ? viewModel.summary.reclaimableBytes : 0,
                              highlightTitle: "Kann frei werden")
                        .card(padding: 18)
                }
                HistoryStrip()
            }
            .padding(Theme.pagePadding)
            .frame(maxWidth: 980)
            .frame(maxWidth: .infinity)
        }
        .animation(Theme.spring, value: viewModel.phase)
        .sheet(item: Binding(get: { model.junk.pendingPlan }, set: { model.junk.pendingPlan = $0 })) { plan in
            DeletionPreviewSheet(plan: plan, protection: model.junk.protection) { model.junk.clean($0) }
        }
    }

    @ViewBuilder
    private func hero(_ viewModel: SmartScanViewModel) -> some View {
        VStack(spacing: 18) {
            SmartScanButton(phase: viewModel.phase, progress: viewModel.overallProgress) {
                viewModel.phase == .scanning ? viewModel.cancel() : viewModel.start()
            }

            switch viewModel.phase {
            case .idle:
                VStack(spacing: 6) {
                    Text("Bereit für einen Smart Scan").font(.title.weight(.semibold))
                    Text("Ein Klick prüft Junk, große Dateien und Duplikate gleichzeitig. Gelöscht wird erst, wenn du es bestätigst.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 520)
                }
            case .scanning:
                VStack(spacing: 6) {
                    Text("Dein Mac wird geprüft …").font(.title.weight(.semibold))
                    Text("Du kannst währenddessen andere Bereiche öffnen – der Scan läuft weiter.")
                        .foregroundStyle(.secondary)
                }
            case .done:
                let summary = viewModel.summary
                VStack(spacing: 10) {
                    BigNumber(bytes: summary.reclaimableBytes, tint: SweepModule.smartScan.tint, size: 56)
                    Text("können sofort frei werden – \(ByteFormat.string(summary.junkBytes)) Junk und \(ByteFormat.string(summary.duplicateBytes)) in \(counted(summary.duplicateCount, "doppelten Datei", "doppelten Dateien")).")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    HStack(spacing: 10) {
                        Button {
                            model.junk.prepareClean()
                        } label: {
                            Label("Junk jetzt aufräumen", systemImage: "sparkles")
                        }
                        .buttonStyle(.prominent(SweepModule.junk.tint))
                        .disabled(model.junk.selection.isEmpty)
                        Button("Duplikate ansehen") { model.selection = .duplicates }
                            .controlSize(.large)
                            .disabled(model.duplicates.groups.isEmpty)
                    }
                    if let outcome = model.junk.lastOutcome {
                        Label("\(ByteFormat.string(outcome.freedBytes)) in den Papierkorb gelegt", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .transition(.opacity)
                    }
                }
                .transition(.scale(scale: 0.95).combined(with: .opacity))
            }
        }
        .padding(.top, 8)
    }
}

/// The big round start button with an animated ring while scanning.
private struct SmartScanButton: View {
    let phase: SmartScanViewModel.Phase
    let progress: Double
    let action: () -> Void
    @State private var rotation = 0.0
    @State private var hovering = false

    var body: some View {
        let tint = SweepModule.smartScan.tint
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.08))
                    .frame(width: 210, height: 210)
                Circle()
                    .stroke(tint.opacity(0.15), lineWidth: 8)
                    .frame(width: 180, height: 180)
                if phase == .scanning {
                    Circle()
                        .trim(from: 0, to: max(0.03, progress))
                        .stroke(AngularGradient(colors: [tint.opacity(0.4), tint, SweepModule.junk.tint], center: .center),
                                style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: 180, height: 180)
                        .animation(.easeOut(duration: 0.4), value: progress)
                    Circle()
                        .trim(from: 0, to: 0.12)
                        .stroke(tint.opacity(0.35), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .frame(width: 204, height: 204)
                        .rotationEffect(.degrees(rotation))
                }
                Circle()
                    .fill(LinearGradient(colors: [tint, SweepModule.junk.tint.shaded(by: 0.1)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 150, height: 150)
                    .shadow(color: tint.opacity(0.35), radius: hovering ? 22 : 14, y: 6)
                VStack(spacing: 4) {
                    Image(systemName: phase == .scanning ? "stop.fill" : "sparkles")
                        .font(.system(size: 34, weight: .semibold))
                        .contentTransition(.symbolEffect(.replace))
                    Text(phase == .scanning ? "Stopp" : phase == .done ? "Erneut" : "Scannen")
                        .font(.headline)
                }
                .foregroundStyle(.white)
            }
            .scaleEffect(hovering ? 1.03 : 1)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Theme.spring, value: hovering)
        .keyboardShortcut("r", modifiers: .command)
        .onChange(of: phase) { _, newPhase in
            if newPhase == .scanning {
                rotation = 0
                withAnimation(.linear(duration: 1.6).repeatForever(autoreverses: false)) { rotation = 360 }
            } else {
                withAnimation(.default) { rotation = 0 }
            }
        }
        .accessibilityLabel(phase == .scanning ? "Smart Scan stoppen" : "Smart Scan starten")
    }
}

private struct PartCard: View {
    let part: SmartScanViewModel.Part
    let viewModel: SmartScanViewModel
    let open: () -> Void

    var body: some View {
        let state = viewModel.state(of: part)
        Button(action: open) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    ModuleIcon(module: part.module, size: 34)
                    Spacer()
                    switch state {
                    case .waiting:
                        EmptyView()
                    case .running:
                        ProgressView().controlSize(.small)
                    case .done:
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                Text(part.module.title).font(.headline)
                Group {
                    switch state {
                    case .waiting:
                        Text(part.module.subtitle).foregroundStyle(.secondary)
                    case .running:
                        Text(viewModel.detail(for: part).isEmpty ? "Läuft …" : viewModel.detail(for: part))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    case .done:
                        result
                    }
                }
                .font(.callout)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .topLeading)
            }
            .card(padding: 18)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(Theme.spring, value: state)
    }

    @ViewBuilder
    private var result: some View {
        let summary = viewModel.summary
        switch part {
        case .junk:
            BigNumber(bytes: summary.junkBytes, caption: "Junk gefunden", tint: part.module.tint, size: 28)
        case .largeFiles:
            BigNumber(bytes: summary.largeFileBytes, caption: "in \(counted(summary.largeFileCount, "großen Datei", "großen Dateien")) zum Prüfen", tint: part.module.tint, size: 28)
        case .duplicates:
            BigNumber(bytes: summary.duplicateBytes, caption: "in \(counted(summary.duplicateCount, "überzähligen Kopie", "überzähligen Kopien"))", tint: part.module.tint, size: 28)
        }
    }
}

private struct AccessReminder: View {
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "lock.shield").font(.title2).foregroundStyle(SweepModule.permissions.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text("Mehr finden mit Festplattenvollzugriff").font(.headline)
                Text("Ohne die Freigabe überspringt Sweep geschützte Bereiche wie App-Container und Mail.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("So geht’s", action: action)
        }
        .card(padding: 14)
    }
}

/// A calm line about what Sweep has done so far.
private struct HistoryStrip: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let log = model.activityLog
        if let last = log.entries.first {
            Button {
                model.selection = .activity
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "clock.arrow.circlepath").foregroundStyle(SweepModule.activity.tint)
                    Text("Bisher mit Sweep entfernt: **\(ByteFormat.string(log.totalFreedBytes))** · zuletzt „\(last.title)“ \(last.date.relativeDescription)")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                }
                .font(.callout)
                .padding(.horizontal, 4)
            }
            .buttonStyle(.plain)
        }
    }
}
