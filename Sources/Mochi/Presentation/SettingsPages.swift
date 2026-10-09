import SwiftUI

struct MainWindowSettingsView: View {
  @ObservedObject var manager: ServiceManager

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 22) {
        PageHeader(
          eyebrow: "Mochi", title: "Settings",
          subtitle: "Tune your cozy local stack and check how it is reachable.",
          symbol: "gearshape.fill")
        HardwareProfileCard(manager: manager)
        NetworkDiagnosticsView(manager: manager)
        VStack(alignment: .leading, spacing: 12) {
          SectionHeading(
            "General preferences", subtitle: "App behavior shared with macOS Settings.",
            symbol: "slider.horizontal.3")
          ThemeSettingsSection()
          LaunchAtLoginSection(manager: manager)
        }
      }
      .padding(.horizontal, 36).padding(.vertical, 32)
    }
    .background(AppTheme.pageBackground)
  }
}

struct NetworkDiagnosticsView: View {
  @ObservedObject var manager: ServiceManager
  @State private var localNetworkAddress: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      SectionHeading(
        "Network diagnostics", subtitle: "Review addresses and test Tailscale connectivity.",
        symbol: "network")
      localNetworkCard
      tailscaleCard
    }
  }

  private var localNetworkCard: some View {
    HStack(spacing: 14) {
      Image(systemName: "wifi").font(.title2.weight(.semibold)).foregroundStyle(AppTheme.accent)
        .frame(width: 42, height: 42).background(
          AppTheme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
      VStack(alignment: .leading, spacing: 3) {
        Text("Local network address").font(.headline)
        Text(localNetworkAddress ?? "No local network IPv4 address detected.").font(.caption)
          .foregroundStyle(.secondary).textSelection(.enabled)
      }
      Spacer()
      if let localNetworkAddress {
        Button {
          NSPasteboard.general.clearContents()
          NSPasteboard.general.setString(localNetworkAddress, forType: .string)
        } label: {
          Label("Copy address", systemImage: "doc.on.doc")
        }
        .labelStyle(.iconOnly).buttonStyle(AppleIconButtonStyle()).help(
          "Copy local network address")
      }
    }
    .appCard()
    .task { localNetworkAddress = await manager.localNetworkIP() }
  }

  private var tailscaleCard: some View {
    let diagnostic = manager.latestTailscaleDiagnostic
    return HStack(spacing: 14) {
      Image(systemName: diagnostic?.symbolName ?? "network").font(.title2.weight(.semibold))
        .foregroundStyle(AppTheme.color(for: diagnostic?.tone ?? .neutral))
        .frame(width: 42, height: 42)
        .background(
          AppTheme.color(for: diagnostic?.tone ?? .neutral).opacity(0.12),
          in: RoundedRectangle(cornerRadius: 12))
      VStack(alignment: .leading, spacing: 3) {
        Text(diagnostic?.title ?? "Tailscale connectivity").font(.headline)
        Text(
          diagnostic.map {
            [$0.peer.map { "Peer: \($0)." }, $0.guidance].compactMap { $0 }.joined(separator: " ")
          } ?? "Test an online peer to detect direct, relayed, or possibly blocked connectivity."
        )
        .font(.caption).foregroundStyle(.secondary)
      }
      Spacer()
      Button(manager.isTestingTailscale ? "Testing…" : "Test Tailscale") {
        Task { await manager.testTailscale() }
      }
      .buttonStyle(AppleSecondaryButtonStyle()).disabled(manager.isTestingTailscale)
    }
    .appCard()
  }
}
