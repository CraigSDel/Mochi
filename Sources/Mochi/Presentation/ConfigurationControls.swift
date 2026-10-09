import SwiftUI

struct ConfigurationField<Content: View>: View {
  let title: String
  let help: PerformanceSettingHelp?
  let content: Content

  init(_ title: String, help: PerformanceSettingHelp? = nil, @ViewBuilder content: () -> Content) {
    self.title = title
    self.help = help
    self.content = content()
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 4) {
        Text(title.uppercased())
          .font(.caption2.weight(.semibold))
          .tracking(0.6)
          .foregroundStyle(AppTheme.secondaryText)
        if let help { SettingInfoButton(help: help) }
      }
      content
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

struct ModelSelector: View {
  let title: String
  let options: [ModelOption]
  let selection: String
  let onSelect: (ModelOption) -> Void

  var body: some View {
    ConfigurationField(title) {
      Menu {
        ForEach(options) { option in
          Button {
            onSelect(option)
          } label: {
            if option.id == selection {
              Label(optionLabel(option), systemImage: "checkmark")
            } else {
              Text(optionLabel(option))
            }
          }
        }
      } label: {
        HStack(spacing: 10) {
          Text(selectedLabel)
            .lineLimit(1)
            .foregroundStyle(AppTheme.primaryText)
          Spacer(minLength: 8)
          Image(systemName: "chevron.up.chevron.down")
            .font(.caption.weight(.semibold))
            .foregroundStyle(AppTheme.accent)
        }
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .frame(maxWidth: .infinity, alignment: .leading)
      .appInputSurface()
    }
  }

  private var selectedLabel: String {
    guard let option = options.first(where: { $0.id == selection }) else {
      return "Choose a model"
    }
    return optionLabel(option)
  }

  private func optionLabel(_ option: ModelOption) -> String {
    "\(option.name) — \(option.detail)"
  }
}

struct ThemedMenuPicker<Value: Hashable>: View {
  let choices: [(label: String, value: Value)]
  @Binding var selection: Value

  var body: some View {
    Menu {
      ForEach(choices.indices, id: \.self) { index in
        let choice = choices[index]
        Button {
          selection = choice.value
        } label: {
          if choice.value == selection {
            Label(choice.label, systemImage: "checkmark")
          } else {
            Text(choice.label)
          }
        }
      }
    } label: {
      HStack(spacing: 10) {
        Text(choices.first(where: { $0.value == selection })?.label ?? "Choose")
          .lineLimit(1)
          .foregroundStyle(AppTheme.primaryText)
        Spacer(minLength: 8)
        Image(systemName: "chevron.up.chevron.down")
          .font(.caption.weight(.semibold))
          .foregroundStyle(AppTheme.accent)
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .frame(maxWidth: .infinity, alignment: .leading)
    .appInputSurface()
  }
}

struct CatalogVisibilityPicker: View {
  @Binding var includeCatalog: Bool

  var body: some View {
    ThemedMenuPicker(
      choices: [
        ("Show recommendations", true),
        ("Installed only", false),
      ],
      selection: $includeCatalog
    )
    .frame(width: 240)
    .help("Choose whether model selectors include catalog recommendations")
  }
}

enum ModelCatalogPreferences {
  static func key(for serviceID: ServiceID) -> String {
    "services.\(serviceID.rawValue).includeCatalog"
  }
}

struct ContextSizeSlider: View {
  @Binding var value: Int
  let assessment: MemoryAssessment

  private var index: Binding<Double> {
    Binding(
      get: {
        Double(ContextSizeOptions.values.firstIndex(of: ContextSizeOptions.normalized(value)) ?? 0)
      },
      set: { newValue in
        let index = min(max(Int(newValue.rounded()), 0), ContextSizeOptions.values.count - 1)
        value = ContextSizeOptions.values[index]
      }
    )
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Text("Context length")
          .font(.subheadline.weight(.semibold))
        Spacer()
        Text(ContextSizeOptions.label(for: value))
          .font(.system(.body, design: .rounded).weight(.semibold))
          .foregroundStyle(AppTheme.accent)
      }
      Slider(value: index, in: 0...Double(ContextSizeOptions.values.count - 1), step: 1)
        .accessibilityLabel("Context length")
        .accessibilityValue("\(ContextSizeOptions.normalized(value)) tokens")
      HStack {
        ForEach(ContextSizeOptions.values, id: \.self) { option in
          Text(ContextSizeOptions.label(for: option))
            .font(.caption2)
            .foregroundStyle(.secondary)
          if option != ContextSizeOptions.values.last { Spacer(minLength: 0) }
        }
      }
      Label(assessment.message, systemImage: assessmentSymbol)
        .font(.caption)
        .foregroundStyle(assessmentColor)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityLabel("Memory assessment: \(assessment.message)")
    }
  }

  private var assessmentSymbol: String {
    switch assessment.severity {
    case .safe: "checkmark.circle.fill"
    case .caution: "exclamationmark.triangle.fill"
    case .high: "exclamationmark.octagon.fill"
    case .unverified: "questionmark.circle.fill"
    }
  }

  private var assessmentColor: Color {
    switch assessment.severity {
    case .safe: .green
    case .caution: .orange
    case .high: .red
    case .unverified: .secondary
    }
  }
}
