import AppKit
import SwiftUI

struct SetupCommandCard: View {
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
