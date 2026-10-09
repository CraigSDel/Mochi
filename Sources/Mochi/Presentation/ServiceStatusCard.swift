import AppKit
import SwiftUI

struct ServiceStatusCard: View {
  let service: ServiceSnapshot
  @ObservedObject var manager: ServiceManager

  private var canStart: Bool {
    service.state.canStart && service.definition.supported
      && manager.validationIssues(for: service.id).isEmpty
  }
  private var canStop: Bool { service.state.canStop && service.pid != nil }

  var body: some View {
    HStack(spacing: 12) {
      VStack(alignment: .leading, spacing: 5) {
        Text(service.statusText)
          .font(.headline)
          .foregroundStyle(service.state == .failed ? Color.red : Color.primary)
        Text(
          service.state == .running
            ? "The service is responding to health checks."
            : "Configuration remains available while the service is idle."
        )
        .font(.caption).foregroundStyle(.secondary)
      }
      Spacer()
      statusCardActions
    }
    .appCard()
  }

  @ViewBuilder
  private var statusCardActions: some View {
    ViewThatFits(in: .horizontal) {
      HStack(spacing: 12) {
        connectionMetadata
        serviceActions
      }
      VStack(alignment: .trailing, spacing: 10) {
        connectionMetadata
        serviceActions
      }
    }
  }

  @ViewBuilder
  private var connectionMetadata: some View {
    if let endpoint = service.endpoint {
      HStack(spacing: 8) {
        MetadataLabel(title: "Endpoint", value: endpoint, symbol: "network")
        Button {
          NSPasteboard.general.clearContents()
          NSPasteboard.general.setString(endpoint, forType: .string)
        } label: {
          Label("Copy endpoint", systemImage: "doc.on.doc")
        }
        .labelStyle(.iconOnly)
        .buttonStyle(AppleIconButtonStyle())
        .help("Copy endpoint")
      }
      .textSelection(.enabled)
    } else {
      MetadataLabel(
        title: "Port", value: "\(manager.configuration(for: service.id).port)", symbol: "number")
    }
  }

  private var serviceActions: some View {
    HStack(spacing: 8) {
      Button("Stop", role: .destructive) { Task { await manager.stop(service.id) } }
        .buttonStyle(AppleDestructiveButtonStyle())
        .disabled(!canStop)
      Button("Start Service") { attemptStart(service.id, manager: manager) }
        .buttonStyle(ApplePrimaryButtonStyle())
        .disabled(!canStart)
    }
  }
}
