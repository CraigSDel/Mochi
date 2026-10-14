import AppKit
import SwiftUI

struct ConversationRow: View {
  let conversation: ChatConversation
  let isSelected: Bool
  let onSelect: () -> Void
  let onDelete: () -> Void

  var body: some View {
    HStack(spacing: 8) {
      Button(action: onSelect) {
        VStack(alignment: .leading, spacing: 4) {
          Text(conversation.title).font(.subheadline.weight(.medium)).lineLimit(2)
          Text(conversation.modelName).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }.frame(maxWidth: .infinity, alignment: .leading)
      }.buttonStyle(.plain)
      Button(action: onDelete) { Image(systemName: "trash") }
        .buttonStyle(AppleIconButtonStyle()).help("Delete conversation")
    }
    .padding(9)
    .background(
      isSelected ? AppTheme.accent.opacity(0.13) : Color.clear,
      in: RoundedRectangle(cornerRadius: 10))
  }
}

struct ChatMessageBubble: View {
  let message: ChatMessage
  let onRegenerate: (() -> Void)?

  var body: some View {
    HStack {
      if message.role == .assistant { bubble } else { Spacer(minLength: 70); bubble }
    }
  }

  private var bubble: some View {
    VStack(alignment: .leading, spacing: 5) {
      Text(message.role == .assistant ? "Mochi" : "You")
        .font(.caption.weight(.semibold)).foregroundStyle(AppTheme.accent)
      Text(message.content.isEmpty ? "Generating…" : message.content)
        .textSelection(.enabled).font(.body).frame(maxWidth: 650, alignment: .leading)
      if let onRegenerate {
        Button("Regenerate", action: onRegenerate)
          .buttonStyle(AppleSecondaryButtonStyle())
          .disabled(message.content.isEmpty)
      }
    }
    .padding(14)
    .background(message.role == .assistant ? AppTheme.surface : AppTheme.accent.opacity(0.12),
      in: RoundedRectangle(cornerRadius: 14))
  }
}

struct ClientExportSheet: View {
  let service: ChatServiceOption
  let export: ClientConfigurationExport
  @Environment(\.dismiss) private var dismiss
  @State private var shellSelected = false

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      PageHeader(
        eyebrow: "Client setup", title: "Connect \(service.name)",
        subtitle: "Copy configuration for an OpenAI-compatible client.", symbol: "link")
      Picker("Format", selection: $shellSelected) {
        Text("JSON").tag(false); Text("Shell").tag(true)
      }.pickerStyle(.segmented)
      Text(shellSelected ? export.shell : export.json)
        .font(.system(.body, design: .monospaced)).textSelection(.enabled)
        .frame(maxWidth: .infinity, minHeight: 130, alignment: .topLeading)
        .padding(12)
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
      Label(export.warning, systemImage: "lock.shield").font(.caption).foregroundStyle(.secondary)
      HStack {
        Spacer()
        Button("Cancel") { dismiss() }.buttonStyle(AppleSecondaryButtonStyle())
        Button("Copy") {
          NSPasteboard.general.clearContents()
          NSPasteboard.general.setString(shellSelected ? export.shell : export.json, forType: .string)
          dismiss()
        }.buttonStyle(ApplePrimaryButtonStyle())
      }
    }.padding(28).frame(width: 560)
  }
}
