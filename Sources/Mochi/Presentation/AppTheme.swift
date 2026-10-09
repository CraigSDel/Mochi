import AppKit
import SwiftUI

enum AppTheme {
  static let mochiPink = adaptiveColor(
    light: NSColor(red: 0.98, green: 0.77, blue: 0.81, alpha: 1),
    dark: NSColor(red: 0.52, green: 0.28, blue: 0.35, alpha: 1)
  )
  static let mochiCream = adaptiveColor(
    light: NSColor(red: 1, green: 0.965, blue: 0.91, alpha: 1),
    dark: NSColor(red: 0.24, green: 0.20, blue: 0.18, alpha: 1)
  )
  static let mochiMatcha = adaptiveColor(
    light: NSColor(red: 0.72, green: 0.82, blue: 0.62, alpha: 1),
    dark: NSColor(red: 0.40, green: 0.52, blue: 0.34, alpha: 1)
  )
  static let mochiLavender = adaptiveColor(
    light: NSColor(red: 0.84, green: 0.75, blue: 0.98, alpha: 1),
    dark: NSColor(red: 0.33, green: 0.25, blue: 0.48, alpha: 1)
  )
  static let accent = adaptiveColor(
    light: NSColor(red: 0, green: 0.443, blue: 0.89, alpha: 1),
    dark: NSColor(red: 0.039, green: 0.518, blue: 1, alpha: 1)
  )
  static let accentPressed = adaptiveColor(
    light: NSColor(red: 0, green: 0.333, blue: 0.776, alpha: 1),
    dark: NSColor(red: 0, green: 0.408, blue: 0.86, alpha: 1)
  )
  static let surface = adaptiveColor(
    light: NSColor(red: 0.992, green: 0.973, blue: 0.949, alpha: 1),
    dark: NSColor(red: 0.185, green: 0.17, blue: 0.17, alpha: 1)
  )
  static let pageBackground = adaptiveColor(
    light: NSColor(red: 1, green: 0.988, blue: 0.97, alpha: 1),
    dark: NSColor(red: 0.12, green: 0.105, blue: 0.105, alpha: 1))
  static let primaryText = Color(nsColor: .labelColor)
  static let secondaryText = Color(nsColor: .secondaryLabelColor)
  static let tertiaryText = Color(nsColor: .tertiaryLabelColor)
  static let separator = Color(nsColor: .separatorColor)
  static let cornerRadius: CGFloat = 18

  static var mochiBackdrop: LinearGradient {
    LinearGradient(
      colors: [pageBackground, mochiPink.opacity(0.16), mochiLavender.opacity(0.12), pageBackground],
      startPoint: .topLeading,
      endPoint: .bottomTrailing
    )
  }

  private static func adaptiveColor(light: NSColor, dark: NSColor) -> Color {
    Color(
      nsColor: NSColor(name: nil) { appearance in
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
    content.padding(padding).background(
      AppTheme.surface,
      in: RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous))
  }
}

extension View {
  func appCard(padding: CGFloat = 18) -> some View { modifier(AppCardModifier(padding: padding)) }

  func appInputSurface() -> some View {
    padding(.horizontal, 12)
      .frame(minHeight: 36)
      .background(
        AppTheme.pageBackground.opacity(0.72),
        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
      )
      .overlay {
        RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(
          AppTheme.separator.opacity(0.45), lineWidth: 1)
      }
  }
}
