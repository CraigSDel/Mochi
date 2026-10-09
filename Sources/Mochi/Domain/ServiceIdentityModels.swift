import Foundation

enum ServiceID: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
  case llamaChat, autocomplete, embeddings
  var id: String { rawValue }
}

enum SidebarDestination: Hashable {
  case overview, setup, models, recommendations, settings
  case service(ServiceID)
  static let initial: SidebarDestination = .overview
}

enum ServiceState: String, Codable, Sendable {
  case unavailable, stopped, starting, running, stopping, failed, external

  var displayName: String {
    switch self {
    case .unavailable: "Unavailable"
    case .stopped: "Stopped"
    case .starting: "Starting"
    case .running: "Running"
    case .stopping: "Stopping"
    case .failed: "Needs attention"
    case .external: "External"
    }
  }

  var symbolName: String {
    switch self {
    case .unavailable: "slash.circle.fill"
    case .stopped: "circle"
    case .starting, .stopping: "clock.fill"
    case .running: "checkmark.circle.fill"
    case .failed: "exclamationmark.triangle.fill"
    case .external: "link.circle.fill"
    }
  }

  var tone: StatusTone {
    switch self {
    case .running: .success
    case .starting, .stopping: .warning
    case .failed: .danger
    case .external: .accent
    case .unavailable, .stopped: .neutral
    }
  }

  var canStart: Bool { [.stopped, .failed, .unavailable].contains(self) }
  var canStop: Bool { [.running, .starting].contains(self) }
}

enum StatusTone: String, CaseIterable, Sendable {
  case accent, success, warning, danger, neutral
}

extension ServiceID {
  var symbolName: String {
    switch self {
    case .llamaChat: "bubble.left.and.bubble.right.fill"
    case .autocomplete: "chevron.left.forwardslash.chevron.right"
    case .embeddings: "point.3.connected.trianglepath.dotted"
    }
  }
}

enum BindMode: String, Codable, CaseIterable, Identifiable, Sendable {
  case tailscale, localhost, lan
  var id: String { rawValue }
  var title: String {
    switch self {
    case .tailscale: "Tailscale"
    case .localhost: "Localhost"
    case .lan: "Local network"
    }
  }
}

enum DownloadPolicy: String, Codable, CaseIterable, Identifiable, Sendable {
  case cachedOnly, allowDownloads
  var id: String { rawValue }
  var title: String { self == .cachedOnly ? "Cached only" : "Allow downloads" }
}
