import SwiftUI

struct BeginnerPerformanceControls: View {
  @Binding var context: Int
  let generation: Binding<GenerationProfile>?
  let role: RecommendationRole
  let assessment: MemoryAssessment

  private var contextIndex: Binding<Double> {
    Binding(
      get: {
        Double(
          ContextSizeOptions.values.firstIndex(of: ContextSizeOptions.normalized(context)) ?? 0)
      },
      set: {
        context =
          ContextSizeOptions.values[
            min(max(Int($0.rounded()), 0), ContextSizeOptions.values.count - 1)]
      })
  }
  private var responseIndex: Binding<Double> {
    Binding(
      get: {
        Double(
          PerformanceTuningPresentation.responseOptions.firstIndex(
            of: PerformanceTuningPresentation.responseValue(
              for: generation?.wrappedValue, role: role)) ?? 1)
      },
      set: { index in
        guard let generation else { return }
        var value = generation.wrappedValue
        let options = PerformanceTuningPresentation.responseOptions
        PerformanceTuningPresentation.setResponseValue(
          options[min(max(Int(index.rounded()), 0), options.count - 1)], on: &value, role: role)
        generation.wrappedValue = value
      }
    )
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text(
        "Longer context remembers more conversation. Longer responses can take more time and memory."
      )
      .font(.caption).foregroundStyle(.secondary)
      slider(
        title: "Context length", value: contextIndex, label: ContextSizeOptions.label(for: context),
        options: ContextSizeOptions.values.map(ContextSizeOptions.label))
      if generation != nil {
        slider(
          title: "Response length", value: responseIndex,
          label: PerformanceTuningPresentation.responseLabel(
            for: generation?.wrappedValue, role: role),
          options: PerformanceTuningPresentation.responseLabels)
      }
      let status = PerformanceTuningPresentation.memoryStatus(for: assessment.severity)
      Label(status.message, systemImage: status.symbol).font(.caption.weight(.medium))
        .foregroundStyle(status.color)
        .accessibilityLabel("Memory status: \(status.message)")
    }
  }

  private func slider(title: String, value: Binding<Double>, label: String, options: [String])
    -> some View
  {
    VStack(alignment: .leading, spacing: 7) {
      HStack {
        Text(title).font(.subheadline.weight(.semibold))
        Spacer()
        Text(label).font(.subheadline.weight(.semibold)).foregroundStyle(AppTheme.accent)
      }
      Slider(value: value, in: 0...Double(options.count - 1), step: 1).accessibilityLabel(title)
        .accessibilityValue(label)
      HStack {
        ForEach(options.indices, id: \.self) { index in
          Text(options[index]).font(.caption2).foregroundStyle(.secondary)
          if index < options.count - 1 { Spacer(minLength: 0) }
        }
      }
    }
  }
}
