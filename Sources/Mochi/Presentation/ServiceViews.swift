import AppKit
import SwiftUI

struct ServiceDetail: View {
  let service: ServiceSnapshot
  @ObservedObject var manager: ServiceManager
  @ObservedObject var recommendations: RecommendationStore
  let fileReveal: any FileRevealClient
  let openModels: () -> Void
  @State private var logsExpanded = false

  private var logPreview: String {
    let lines = service.logText.split(separator: "\n", omittingEmptySubsequences: false)
    return lines.suffix(4).joined(separator: "\n")
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        HStack(alignment: .center) {
          PageHeader(
            eyebrow: service.definition.runtime,
            title: service.definition.name,
            subtitle: service.definition.detail,
            symbol: service.id.symbolName,
            tone: service.state.tone
          )
          Spacer()
          StatusBadge(state: service.state)
        }

        ServiceStatusCard(service: service, manager: manager)

        ServiceConfigurationEditor(
          serviceID: service.id, manager: manager, recommendations: recommendations,
          openModels: openModels)

        VStack(alignment: .leading, spacing: 12) {
          HStack {
            SectionHeading(
              "Runtime log", subtitle: "Recent output from this service.", symbol: "terminal")
            Spacer()
            Button {
              logsExpanded.toggle()
            } label: {
              Label(
                logsExpanded ? "Collapse" : "Expand",
                systemImage: logsExpanded ? "chevron.up" : "chevron.down")
            }
            .buttonStyle(AppleSecondaryButtonStyle())
          }
          Text(
            service.logText.isEmpty
              ? "No log output yet." : (logsExpanded ? service.logText : logPreview)
          )
          .font(.system(.caption, design: .monospaced))
          .foregroundStyle(service.logText.isEmpty ? .secondary : .primary)
          .textSelection(.enabled)
          .frame(maxWidth: .infinity, minHeight: logsExpanded ? 220 : 72, alignment: .topLeading)
          .padding(12)
          .background(
            Color(nsColor: .textBackgroundColor).opacity(0.72),
            in: RoundedRectangle(cornerRadius: 10))
          HStack {
            Button("Copy") {
              NSPasteboard.general.clearContents()
              NSPasteboard.general.setString(service.logText, forType: .string)
            }
            .buttonStyle(AppleSecondaryButtonStyle())
            .disabled(service.logText.isEmpty)
            Button("Reveal in Finder") { fileReveal.reveal(manager.logURL(service.id)) }
              .buttonStyle(AppleSecondaryButtonStyle())
            Spacer()
            Button("Clear", role: .destructive) { manager.clearLog(service.id) }
              .buttonStyle(AppleDestructiveButtonStyle())
              .disabled(service.logText.isEmpty)
          }
        }
        .appCard()
      }
      .padding(.horizontal, 36)
      .padding(.vertical, 32)
    }
    .background(AppTheme.pageBackground)
  }
}
