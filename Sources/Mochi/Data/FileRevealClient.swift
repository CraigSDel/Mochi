import AppKit

@MainActor
protocol FileRevealClient: AnyObject {
  func reveal(_ url: URL)
}

@MainActor
final class LiveFileRevealClient: FileRevealClient {
  func reveal(_ url: URL) {
    NSWorkspace.shared.activateFileViewerSelecting([url])
  }
}
