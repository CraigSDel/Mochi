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
    static let pageBackground = adaptiveColor(light: .white, dark: NSColor(red: 0.11, green: 0.11, blue: 0.118, alpha: 1))
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
        content.padding(padding).background(AppTheme.surface, in: RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous))
    }
}

extension View {
    func appCard(padding: CGFloat = 18) -> some View { modifier(AppCardModifier(padding: padding)) }

    func appInputSurface() -> some View {
        padding(.horizontal, 12)
            .frame(minHeight: 36)
            .background(AppTheme.pageBackground.opacity(0.72), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(AppTheme.separator.opacity(0.45), lineWidth: 1) }
    }
}
