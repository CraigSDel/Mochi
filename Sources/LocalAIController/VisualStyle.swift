import SwiftUI

enum AppTheme {
    static let accent = Color(red: 0.06, green: 0.63, blue: 0.56)
    static let mint = Color(red: 0.36, green: 0.88, blue: 0.70)
    static let cornerRadius: CGFloat = 16

    static func color(for tone: StatusTone) -> Color {
        switch tone {
        case .accent: accent
        case .success: .green
        case .warning: .orange
        case .danger: .red
        case .neutral: .secondary
        }
    }
}

struct AppCardModifier: ViewModifier {
    var padding: CGFloat = 18

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous)
                    .stroke(.primary.opacity(0.08), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.06), radius: 14, y: 5)
    }
}

extension View {
    func appCard(padding: CGFloat = 18) -> some View {
        modifier(AppCardModifier(padding: padding))
    }
}

struct BrandMark: View {
    var size: CGFloat = 34

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [AppTheme.mint, AppTheme.accent],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.system(size: size * 0.48, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .shadow(color: AppTheme.accent.opacity(0.25), radius: 7, y: 3)
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
        HStack(alignment: .center, spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(AppTheme.color(for: tone).opacity(0.13))
                Image(systemName: symbol)
                    .font(.system(size: 23, weight: .semibold))
                    .foregroundStyle(AppTheme.color(for: tone))
            }
            .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 3) {
                Text(eyebrow.uppercased())
                    .font(.caption2.weight(.bold))
                    .tracking(1.2)
                    .foregroundStyle(AppTheme.accent)
                Text(title)
                    .font(.system(.title, design: .rounded, weight: .bold))
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
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
