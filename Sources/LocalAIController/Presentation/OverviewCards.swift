import SwiftUI
import AppKit

struct OverviewMetric: View {
    let title: String
    let value: String
    let symbol: String
    let tone: StatusTone

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.title3.weight(.semibold)).foregroundStyle(AppTheme.color(for: tone))
                .frame(width: 36, height: 36)
                .background(AppTheme.color(for: tone).opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 1) {
                Text(value).font(.title2.bold())
                Text(title).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .appCard(padding: 14)
    }
}

struct OverviewServiceCard: View {
    let service: ServiceSnapshot
    @ObservedObject var manager: ServiceManager
    let open: () -> Void

    private var canStart: Bool { service.state.canStart && service.definition.supported && manager.validationIssues(for: service.id).isEmpty }
    private var canStop: Bool { service.state.canStop && service.pid != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                Image(systemName: service.id.symbolName)
                    .font(.title2.weight(.semibold)).foregroundStyle(AppTheme.accent)
                    .frame(width: 42, height: 42)
                    .background(AppTheme.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                Spacer()
                StatusBadge(state: service.state)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(service.definition.name).font(.headline)
                Text(service.definition.detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            HStack {
                Label(service.definition.runtime, systemImage: "gearshape.2")
                Spacer()
                if let endpoint = service.endpoint {
                    Text(endpoint).lineLimit(1).textSelection(.enabled)
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(endpoint, forType: .string)
                    } label: { Image(systemName: "doc.on.doc") }
                        .buttonStyle(AppleIconButtonStyle()).help("Copy endpoint")
                } else {
                    Text("Port \(manager.configuration(for: service.id).port)").lineLimit(1)
                }
            }
            .font(.caption).foregroundStyle(.secondary)
            Divider()
            HStack {
                Button("Open", action: open).buttonStyle(AppleSecondaryButtonStyle())
                Spacer()
                if canStop {
                    Button("Stop", role: .destructive) { Task { await manager.stop(service.id) } }
                        .buttonStyle(AppleDestructiveButtonStyle())
                } else {
                    Button("Start") { attemptStart(service.id, manager: manager) }
                        .buttonStyle(ApplePrimaryButtonStyle()).disabled(!canStart)
                }
            }
        }
        .appCard()
    }
}
