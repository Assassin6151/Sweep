import SwiftUI

enum Theme {
    static let cornerRadius: CGFloat = 14
    static let spring = Animation.spring(response: 0.45, dampingFraction: 0.85)
    static let pagePadding: CGFloat = 28
}

/// A soft, slightly elevated surface that works in light and dark mode.
struct CardBackground: ViewModifier {
    var padding: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    .strokeBorder(.separator.opacity(0.6), lineWidth: 0.5)
            )
    }
}

extension View {
    func card(padding: CGFloat = 16) -> some View { modifier(CardBackground(padding: padding)) }
}

/// The rounded, gradient filled symbol used for module icons.
struct ModuleIcon: View {
    let module: SweepModule
    var size: CGFloat = 28

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(module.gradient)
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: module.symbol)
                    .font(.system(size: size * 0.5, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .shadow(color: module.tint.opacity(0.25), radius: size * 0.12, y: size * 0.05)
    }
}

/// Large, calm numbers ("12,4 GB") with an animated transition.
struct BigNumber: View {
    let value: String
    var unit: String = ""
    var caption: String?
    var tint: Color = .primary
    var size: CGFloat = 44

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: size, weight: .semibold, design: .rounded))
                    .contentTransition(.numericText())
                    .foregroundStyle(tint)
                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: size * 0.42, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            if let caption {
                Text(caption)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

extension BigNumber {
    init(bytes: Int64, caption: String? = nil, tint: Color = .primary, size: CGFloat = 44) {
        let parts = ByteFormat.parts(bytes)
        self.init(value: parts.value, unit: parts.unit, caption: caption, tint: tint, size: size)
    }
}

/// The primary call to action, a large capsule with the module gradient.
struct ProminentButtonStyle: ButtonStyle {
    var tint: Color
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .padding(.horizontal, 22)
            .padding(.vertical, 11)
            .background(
                Capsule().fill(LinearGradient(colors: [tint, tint.shaded(by: 0.2)], startPoint: .top, endPoint: .bottom))
            )
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.45)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .shadow(color: tint.opacity(isEnabled ? 0.3 : 0), radius: 8, y: 3)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == ProminentButtonStyle {
    static func prominent(_ tint: Color) -> ProminentButtonStyle { ProminentButtonStyle(tint: tint) }
}
