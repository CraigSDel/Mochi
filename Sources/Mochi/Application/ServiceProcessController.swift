import Foundation

@MainActor
final class ServiceProcessController {
  private let factory: any ProcessMaking
  private(set) var processes: [ServiceID: Process] = [:]
  private(set) var outputHandles: [ServiceID: FileHandle] = [:]
  private(set) var stopRequested: Set<ServiceID> = []

  init(factory: any ProcessMaking) {
    self.factory = factory
  }

  func makeProcess(
    for serviceID: ServiceID,
    output: FileHandle,
    terminationHandler: @escaping @Sendable (Process) -> Void
  ) -> Process {
    let process = factory.makeProcess()
    process.executableURL = URL(fileURLWithPath: "/bin/bash")
    process.standardOutput = output
    process.standardError = output
    process.terminationHandler = terminationHandler
    outputHandles[serviceID] = output
    return process
  }

  func register(_ process: Process, for serviceID: ServiceID) {
    processes[serviceID] = process
  }

  func process(for serviceID: ServiceID) -> Process? {
    processes[serviceID]
  }

  func requestStop(for serviceID: ServiceID) {
    stopRequested.insert(serviceID)
  }

  func wasStopRequested(for serviceID: ServiceID) -> Bool {
    stopRequested.contains(serviceID)
  }

  func closeOutput(for serviceID: ServiceID) {
    if let handle = outputHandles.removeValue(forKey: serviceID) {
      try? handle.close()
    }
  }

  func removeProcess(for serviceID: ServiceID) {
    processes[serviceID] = nil
  }

  func completeStop(for serviceID: ServiceID) {
    stopRequested.remove(serviceID)
    removeProcess(for: serviceID)
  }
}
