import SwiftUI

struct ThemeSettingsSection: View {
  @AppStorage("appearance.theme") private var themeRawValue = MochiTheme.pink.rawValue

  private var theme: Binding<MochiTheme> {
    Binding(
      get: { MochiTheme(rawValue: themeRawValue) ?? .pink },
      set: { themeRawValue = $0.rawValue }
    )
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      SectionHeading(
        "Theme", subtitle: "Choose a Mochi colour palette for the app.", symbol: "paintpalette")
      Picker("Theme", selection: theme) {
        ForEach(MochiTheme.allCases) { theme in
          Text(theme.title).tag(theme)
        }
      }
      .pickerStyle(.segmented)
      .onChange(of: themeRawValue) { _, rawValue in
        AppTheme.apply(MochiTheme(rawValue: rawValue) ?? .pink)
      }
    }
    .appCard()
    .onAppear { AppTheme.apply(MochiTheme(rawValue: themeRawValue) ?? .pink) }
  }
}
