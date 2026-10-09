import SwiftUI
import AppKit

struct SetupGuideView: View {
    @ObservedObject var manager: ServiceManager

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PageHeader(
                    eyebrow: "Getting started",
                    title: "Set up your local AI stack",
                    subtitle: "Follow these steps to prepare your Mac and make your first request.",
                    symbol: "wand.and.stars"
                )
                setupSummary
                prerequisites
                resources
                commands
                setupSteps
                safetyNotes
            }
            .padding(.horizontal, 36)
            .padding(.vertical, 32)
        }
        .background(AppTheme.pageBackground)
    }

    private var setupSummary: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "checklist")
                .font(.title2.weight(.semibold))
                .foregroundStyle(AppTheme.accent)
                .frame(width: 42, height: 42)
                .background(AppTheme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 5) {
                Text("This app manages configuration and service lifecycle.").font(.headline)
                Text("It does not install runtimes, Tailscale, or models for you. Install those dependencies first, then use the service screens to finish configuration.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("\(manager.services.filter(\.definition.supported).count) of \(manager.services.count) configured services are available on this Mac.")
                    .font(.caption)
                    .foregroundStyle(AppTheme.accent)
            }
        }
        .appCard()
    }

    private var prerequisites: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading("Before you begin", subtitle: "Install and verify the tools your chosen runtime needs.", symbol: "shippingbox")
            SetupChecklistCard(items: [
                ("macOS 14 or later", "This controller is designed for a Mac.", "laptopcomputer"),
                ("llama.cpp", "Install llama-server before starting Chat, Autocomplete, or Embeddings.", "terminal"),
                ("Tailscale, if needed", "Install and connect Tailscale before choosing Tailscale networking.", "network"),
                ("Enough disk space", "Models can be large. Check the model size before downloading.", "internaldrive")
            ])
        }
    }

    private var setupSteps: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading("Set up a service", subtitle: "Complete the same flow for each service you want to use.", symbol: "list.number")
            VStack(spacing: 0) {
                SetupStep(number: 1, title: "Open a service", detail: "Choose a service from the sidebar and confirm its runtime is available.", symbol: "server.rack")
                SetupStep(number: 2, title: "Choose how it is reachable", detail: "Use Localhost for this Mac, Tailscale for your private tailnet, or LAN only on a trusted network.", symbol: "network")
                SetupStep(number: 3, title: "Choose a model and settings", detail: "Review the model, context size, and performance settings. Keep the defaults if you are unsure.", symbol: "slider.horizontal.3")
                SetupStep(number: 4, title: "Start the service", detail: "Use Start on the service screen, or Start All on Overview. Watch the status and runtime log for readiness.", symbol: "play.circle")
                SetupStep(number: 5, title: "Connect your client", detail: "Copy the endpoint shown on the service card. OpenAI-compatible services use the /v1 path.", symbol: "link")
            }
            .appCard(padding: 8)
        }
    }

    private var resources: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading("Install the pieces", subtitle: "Use the official download or build instructions for each dependency.", symbol: "arrow.down.circle")
            VStack(alignment: .leading, spacing: 10) {
                SetupResourceLink(title: "llama.cpp server", detail: "Build or install llama-server, then make sure it is on this app's PATH.", url: "https://github.com/ggml-org/llama.cpp/blob/master/docs/build.md", symbol: "hammer")
                SetupResourceLink(title: "Tailscale for macOS", detail: "Install the client and sign in before selecting Tailscale networking.", url: "https://tailscale.com/docs/install/mac", symbol: "network")
            }
            .appCard()
        }
    }

    private var commands: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading("Copy these commands", subtitle: "Run them in Terminal. The controller never runs setup commands for you.", symbol: "terminal")
            VStack(alignment: .leading, spacing: 14) {
                SetupCommandCard(title: "Check installed tools", detail: "llama-server is required. Tailscale is only needed for Tailscale mode.", command: "command -v llama-server; command -v tailscale")
                SetupCommandCard(title: "Build llama-server", detail: "Use this if you are setting up llama.cpp from source. It builds with Metal enabled on macOS.", command: "git clone https://github.com/ggml-org/llama.cpp \"$HOME/llama.cpp\"\ncmake -B \"$HOME/llama.cpp/build\" \"$HOME/llama.cpp\"\ncmake --build \"$HOME/llama.cpp/build\" --config Release -t llama-server\nexport PATH=\"$HOME/llama.cpp/build/bin:$PATH\"")
                SetupCommandCard(title: "Connect Tailscale", detail: "Only run this after installing the Tailscale app. Skip it for Localhost mode.", command: "tailscale up\ntailscale ip -4")
            }
        }
    }

    private var safetyNotes: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading("Keep your setup safe", subtitle: "A few choices affect who can reach your API.", symbol: "lock.shield")
            VStack(alignment: .leading, spacing: 10) {
                Label("Prefer Tailscale or Localhost over LAN when possible.", systemImage: "checkmark.shield")
                Label("LAN mode exposes an unauthenticated API to your local network.", systemImage: "exclamationmark.triangle")
                Label("The controller will not stop an external process it cannot identify as managed by this app.", systemImage: "hand.raised")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .appCard()
        }
    }
}

private struct SetupChecklistCard: View {
    let items: [(String, String, String)]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], spacing: 12) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                VStack(alignment: .leading, spacing: 7) {
                    Image(systemName: item.2).foregroundStyle(AppTheme.accent)
                    Text(item.0).font(.headline)
                    Text(item.1).font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(AppTheme.pageBackground.opacity(0.62), in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .appCard()
    }
}

private struct SetupStep: View {
    let number: Int
    let title: String
    let detail: String
    let symbol: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Text("\(number)")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(AppTheme.accent, in: Circle())
            Image(systemName: symbol)
                .foregroundStyle(AppTheme.accent)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
    }
}

private struct SetupResourceLink: View {
    let title: String
    let detail: String
    let url: String
    let symbol: String

    var body: some View {
        Link(destination: URL(string: url)!) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .foregroundStyle(AppTheme.accent)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.headline)
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "arrow.up.right.square")
                    .foregroundStyle(AppTheme.accent)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct SetupCommandCard: View {
    let title: String
    let detail: String
    let command: String
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.headline)
                Spacer()
                Button(copied ? "Copied" : "Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(command, forType: .string)
                    copied = true
                    Task {
                        try? await Task.sleep(for: .seconds(2))
                        copied = false
                    }
                }
                .buttonStyle(AppleSecondaryButtonStyle())
            }
            Text(detail).font(.caption).foregroundStyle(.secondary)
            Text(command)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(AppTheme.primaryText)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(AppTheme.pageBackground, in: RoundedRectangle(cornerRadius: 10))
        }
        .appCard(padding: 14)
    }
}
