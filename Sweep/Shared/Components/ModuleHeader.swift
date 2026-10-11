import SwiftUI

/// Title row shown at the top of every module.
struct ModuleHeader<Accessory: View>: View {
    let module: SweepModule
    @ViewBuilder var accessory: () -> Accessory

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            ModuleIcon(module: module, size: 42)
            VStack(alignment: .leading, spacing: 2) {
                Text(module.title)
                    .font(.title2.weight(.semibold))
                Text(module.subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            accessory()
        }
    }
}

extension ModuleHeader where Accessory == EmptyView {
    init(module: SweepModule) {
        self.init(module: module) { EmptyView() }
    }
}

/// Large, centered state for "nothing scanned yet" with a call to action.
struct HeroState<Actions: View>: View {
    let module: SweepModule
    var title: String
    var message: String
    @ViewBuilder var actions: () -> Actions
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(module.tint.opacity(0.12))
                    .frame(width: 150, height: 150)
                Circle()
                    .fill(module.tint.opacity(0.18))
                    .frame(width: 110, height: 110)
                ModuleIcon(module: module, size: 72)
            }
            .scaleEffect(appeared ? 1 : 0.85)
            .opacity(appeared ? 1 : 0)

            VStack(spacing: 6) {
                Text(title)
                    .font(.title2.weight(.semibold))
                Text(message)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 460)
            }
            actions()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { withAnimation(Theme.spring) { appeared = true } }
    }
}

/// Inline progress used while a scan runs.
struct ScanProgressView: View {
    let tint: Color
    let fraction: Double?
    let title: String
    let detail: String
    var onCancel: (() -> Void)?

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .stroke(tint.opacity(0.15), lineWidth: 10)
                if let fraction {
                    Circle()
                        .trim(from: 0, to: max(0.02, fraction))
                        .stroke(tint, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.easeOut(duration: 0.3), value: fraction)
                    Text(fraction, format: .percent.precision(.fractionLength(0)))
                        .font(.system(size: 26, weight: .semibold, design: .rounded))
                        .contentTransition(.numericText())
                } else {
                    ProgressView().controlSize(.large)
                }
            }
            .frame(width: 120, height: 120)

            VStack(spacing: 4) {
                Text(title).font(.headline)
                Text(detail)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 520)
            }
            if let onCancel {
                Button("Abbrechen", role: .cancel, action: onCancel)
                    .controlSize(.large)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
    }
}
