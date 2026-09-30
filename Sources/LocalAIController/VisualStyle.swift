import SwiftUI
import AppKit

enum AppTheme {
    static let accent = adaptiveColor(
        light: NSColor(red: 0, green: 0.443, blue: 0.89, alpha: 1),
        dark: NSColor(red: 0.039, green: 0.518, blue: 1, alpha: 1)
    )
    static let accentPressed = adaptiveColor(
        light: NSColor(red: 0, green: 0.333, blue: 0.776, alpha: 1),
        dark: NSColor(red: 0, green: 0.408, blue: 0.86, alpha: 1)
    )
    static let surface = adaptiveColor(
        light: NSColor(red: 0.961, green: 0.961, blue: 0.969, alpha: 1),
        dark: NSColor(red: 0.173, green: 0.173, blue: 0.18, alpha: 1)
    )
    static let pageBackground = adaptiveColor(
        light: .white,
        dark: NSColor(red: 0.11, green: 0.11, blue: 0.118, alpha: 1)
    )
    static let primaryText = Color(nsColor: .labelColor)
    static let secondaryText = Color(nsColor: .secondaryLabelColor)
    static let tertiaryText = Color(nsColor: .tertiaryLabelColor)
    static let separator = Color(nsColor: .separatorColor)
    static let cornerRadius: CGFloat = 18

    private static func adaptiveColor(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
    }

    static func color(for tone: StatusTone) -> Color {
        switch tone {
        case .accent: accent
        case .success: Color(red: 0.204, green: 0.78, blue: 0.349)
        case .warning: .orange
        case .danger: Color(red: 1, green: 0.231, blue: 0.188)
        case .neutral: secondaryText
        }
    }
}

struct AppCardModifier: ViewModifier {
    var padding: CGFloat = 18

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous))
    }
}

extension View {
    func appCard(padding: CGFloat = 18) -> some View {
        modifier(AppCardModifier(padding: padding))
    }

    func appInputSurface() -> some View {
        padding(.horizontal, 12)
            .frame(minHeight: 36)
            .background(AppTheme.pageBackground.opacity(0.72), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(AppTheme.separator.opacity(0.45), lineWidth: 1)
            }
    }
}

struct BrandMark: View {
    var size: CGFloat = 34

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(AppTheme.accent)
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.system(size: size * 0.48, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct PageHeader: View {
    let eyebrow: String
    let title: String
    let subtitle: String
    let symbol: String
    var tone: StatusTone = .accent

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text(eyebrow.uppercased())
                    .font(.caption.weight(.semibold))
                    .tracking(0.8)
                    .foregroundStyle(AppTheme.accent)
                Text(title)
                    .font(.system(size: 34, weight: .semibold, design: .default))
                    .tracking(-0.7)
                    .foregroundStyle(AppTheme.primaryText)
                Text(subtitle)
                    .font(.system(size: 15))
                    .foregroundStyle(AppTheme.secondaryText)
            }
        }
    }
}

struct ApplePrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .frame(minHeight: 38)
            .background(configuration.isPressed ? AppTheme.accentPressed : AppTheme.accent, in: Capsule())
            .opacity(isEnabled ? (configuration.isPressed ? 0.92 : 1) : 0.4)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct AppleSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(isEnabled ? AppTheme.accent : AppTheme.tertiaryText)
            .padding(.horizontal, 14)
            .frame(minHeight: 36)
            .background(
                isEnabled ? AppTheme.accent.opacity(configuration.isPressed ? 0.2 : 0.11) : AppTheme.separator.opacity(0.12),
                in: Capsule()
            )
            .contentShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct AppleDestructiveButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(isEnabled ? AppTheme.color(for: .danger) : AppTheme.tertiaryText)
            .padding(.horizontal, 14)
            .frame(minHeight: 36)
            .background(
                isEnabled
                    ? AppTheme.color(for: .danger).opacity(configuration.isPressed ? 0.2 : 0.1)
                    : AppTheme.separator.opacity(0.12),
                in: Capsule()
            )
            .contentShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct AppleIconButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isEnabled ? AppTheme.accent : AppTheme.tertiaryText)
            .frame(width: 36, height: 36)
            .background(
                isEnabled ? AppTheme.accent.opacity(configuration.isPressed ? 0.2 : 0.11) : AppTheme.separator.opacity(0.12),
                in: Circle()
            )
            .contentShape(Circle())
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct StatusBadge: View {
    let state: ServiceState

    var body: some View {
        Label(state.displayName, systemImage: state.symbolName)
            .font(.caption.weight(.semibold))
            .foregroundStyle(AppTheme.color(for: state.tone))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(AppTheme.color(for: state.tone).opacity(0.12), in: Capsule())
            .accessibilityLabel("Status: \(state.displayName)")
    }
}

struct CompatibilityBadge: View {
    let compatibility: Compatibility

    private var color: Color {
        switch compatibility {
        case .compatible: .green
        case .unverified: .orange
        case .incompatible: .red
        }
    }

    var body: some View {
        Text(compatibility.rawValue)
            .font(.caption2.weight(.bold))
            .foregroundStyle(color)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(color.opacity(0.12), in: Capsule())
    }
}

struct SectionHeading: View {
    let title: String
    let subtitle: String?
    let symbol: String

    init(_ title: String, subtitle: String? = nil, symbol: String) {
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(AppTheme.accent)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                if let subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary) }
            }
        }
    }
}

struct MetadataLabel: View {
    let title: String
    let value: String
    var symbol: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                if let symbol { Image(systemName: symbol) }
                Text(title.uppercased()).tracking(0.7)
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.tertiary)
            Text(value)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
                .textSelection(.enabled)
        }
    }
}

struct FriendlyEmptyState: View {
    let symbol: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(AppTheme.accent)
            Text(title).font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
        .frame(maxWidth: .infinity, minHeight: 180)
        .appCard()
    }
}
