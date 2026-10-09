import OSLog

enum ServiceLogEvent: Equatable, Sendable {
  case launchAttempt
  case launchFailed
  case launchStarted(pid: Int32)
  case endpointReady
  case ownershipRejected
  case stopRequested
  case processTerminated(status: Int32)
}

protocol ServiceLogging: AnyObject {
  func record(_ event: ServiceLogEvent, serviceID: ServiceID)
}

final class LiveServiceLogger: ServiceLogging {
  private let logger = Logger(subsystem: "local.mochi", category: "services")

  func record(_ event: ServiceLogEvent, serviceID: ServiceID) {
    switch event {
    case .launchAttempt:
      logger.info("launch_attempt service=\(serviceID.rawValue, privacy: .public)")
    case .launchFailed:
      logger.error("launch_failed service=\(serviceID.rawValue, privacy: .public)")
    case .launchStarted(let pid):
      logger.info(
        "launch_started service=\(serviceID.rawValue, privacy: .public) pid=\(pid, privacy: .public)"
      )
    case .endpointReady:
      logger.info("endpoint_ready service=\(serviceID.rawValue, privacy: .public)")
    case .ownershipRejected:
      logger.warning("ownership_rejected service=\(serviceID.rawValue, privacy: .public)")
    case .stopRequested:
      logger.info("stop_requested service=\(serviceID.rawValue, privacy: .public)")
    case .processTerminated(let status):
      logger.info(
        "process_terminated service=\(serviceID.rawValue, privacy: .public) status=\(status, privacy: .public)"
      )
    }
  }
}
