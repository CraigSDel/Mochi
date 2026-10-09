import AppKit
import SwiftUI

enum MochiTheme: String, CaseIterable, Identifiable {
  case pink
  case matcha
  case cream

  var id: String { rawValue }

  var title: String { rawValue.capitalized }
}

@MainActor
enum AppTheme {
  static var selectedTheme: MochiTheme = .pink

  static func apply(_ theme: MochiTheme) {
    selectedTheme = theme
  }

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
  static var accent: Color {
    switch selectedTheme {
    case .pink:
      adaptiveColor(
        light: NSColor(red: 0.76, green: 0.08, blue: 0.32, alpha: 1),
        dark: NSColor(red: 0.86, green: 0.28, blue: 0.43, alpha: 1))
    case .matcha:
      adaptiveColor(
        light: NSColor(red: 0.27, green: 0.49, blue: 0.16, alpha: 1),
        dark: NSColor(red: 0.57, green: 0.74, blue: 0.38, alpha: 1))
    case .cream:
      adaptiveColor(
        light: NSColor(red: 0.52, green: 0.28, blue: 0.12, alpha: 1),
        dark: NSColor(red: 0.88, green: 0.68, blue: 0.43, alpha: 1))
    }
  }

  static var accentPressed: Color {
    switch selectedTheme {
    case .pink:
      adaptiveColor(
        light: NSColor(red: 0.60, green: 0.04, blue: 0.23, alpha: 1),
        dark: NSColor(red: 0.70, green: 0.16, blue: 0.30, alpha: 1))
    case .matcha:
      adaptiveColor(
        light: NSColor(red: 0.19, green: 0.37, blue: 0.10, alpha: 1),
        dark: NSColor(red: 0.40, green: 0.57, blue: 0.24, alpha: 1))
    case .cream:
      adaptiveColor(
        light: NSColor(red: 0.36, green: 0.17, blue: 0.06, alpha: 1),
        dark: NSColor(red: 0.68, green: 0.45, blue: 0.24, alpha: 1))
    }
  }
  static let surface = adaptiveColor(
    light: NSColor(red: 0.985, green: 0.982, blue: 0.978, alpha: 1),
    dark: NSColor(red: 0.145, green: 0.155, blue: 0.17, alpha: 1)
  )
  static var pageBackground: Color {
    switch selectedTheme {
    case .pink:
      adaptiveColor(
        light: NSColor(red: 0.985, green: 0.975, blue: 0.98, alpha: 1),
        dark: NSColor(red: 0.11, green: 0.085, blue: 0.095, alpha: 1))
    case .matcha:
      adaptiveColor(
        light: NSColor(red: 0.975, green: 0.985, blue: 0.965, alpha: 1),
        dark: NSColor(red: 0.09, green: 0.11, blue: 0.08, alpha: 1))
    case .cream:
      adaptiveColor(
        light: NSColor(red: 0.995, green: 0.98, blue: 0.94, alpha: 1),
        dark: NSColor(red: 0.13, green: 0.105, blue: 0.075, alpha: 1))
    }
  }
  static let primaryText = Color(nsColor: .labelColor)
  static let secondaryText = Color(nsColor: .secondaryLabelColor)
  static let tertiaryText = Color(nsColor: .tertiaryLabelColor)
  static let separator = Color(nsColor: .separatorColor)
  static let cornerRadius: CGFloat = 18

  static var mochiBackdrop: LinearGradient {
    LinearGradient(
      colors: [
        pageBackground,
        themeColor.opacity(0.045),
        mochiPink.opacity(selectedTheme == .pink ? 0.02 : 0.035),
        pageBackground,
      ],
      startPoint: .topLeading,
      endPoint: .bottomTrailing
    )
  }

  private static var themeColor: Color {
    switch selectedTheme {
    case .pink: mochiPink
    case .matcha: mochiMatcha
    case .cream: mochiCream
    }
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
  var padding: CGFloat = 20
  func body(content: Content) -> some View {
    content.padding(padding).background(
      AppTheme.surface,
      in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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
