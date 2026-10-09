import Darwin
import Foundation

@MainActor
extension ServiceManager {
  func stop(_ id: ServiceID) async {
    guard let index = services.firstIndex(where: { $0.id == id }),
      let record = processStore.load(id),
      await validate(record)
    else {
      logger.record(.ownershipRejected, serviceID: id)
      if let index = services.firstIndex(where: { $0.id == id }), services[index].state == .external
      {
        services[index].statusText = "External process; not stopped for safety."
      }
      return
    }
    let hasLocalTerminationHandler = processController.process(for: id) != nil
    processController.requestStop(for: id)
    logger.record(.stopRequested, serviceID: id)
    services[index].state = .stopping
    services[index].statusText = "Stopping…"
    appendLog(id, "Stop requested")
    kill(record.pid, SIGTERM)
    for _ in 0..<stopPollAttempts {
      if !(await probe.isProcessRunning(record.pid)) { break }
      try? await Task.sleep(for: .milliseconds(250))
    }
    if await probe.isProcessRunning(record.pid) {
      services[index].state = .running
      services[index].statusText = "Stop timed out; process is still running"
      services[index].pid = record.pid
      appendLog(id, "ERROR: Process did not stop after SIGTERM; ownership retained")
      return
    }
    if !hasLocalTerminationHandler { completeIntentionalStop(id) }
    await refreshStatuses()
  }

  func refreshStatuses() async {
    for index in services.indices {
      let id = services[index].id
      services[index].logText = logStore.tail(id)
      if let record = processStore.load(id), await validate(record) {
        let wasRunning = services[index].state == .running
        let hosts =
          await resolvedHosts(for: record.bindMode ?? .tailscale) ?? ("127.0.0.1", "127.0.0.1")
        let listening = await probe.isPortListening(record.port)
        let healthy =
          listening
          ? await probe.healthResponding(id, port: record.port, host: hosts.health) : false
        let endpoint = Self.endpoint(id, record.port, hosts.display)
        services[index].state = healthy ? .running : .starting
        services[index].statusText =
          healthy ? "Running and healthy at \(endpoint)" : "Process active; waiting for health"
        services[index].pid = record.pid
        services[index].endpoint = endpoint
        if healthy && !wasRunning {
          logger.record(.endpointReady, serviceID: id)
          appendLog(id, "Model available at \(endpoint)")
        }
      } else {
        await markExternalOrStopped(index: index, id: id)
      }
    }
  }

  private func markExternalOrStopped(index: Int, id: ServiceID) async {
    let config = configuration(for: id)
    if await probe.isPortListening(config.port) {
      if validatedProcessRoots[id] == nil {
        validatedProcessRoots[id] = .noOwnedPID(reason: "Port is occupied by an external process")
      }
      processStore.remove(id)
      let hosts = await resolvedHosts(for: config.bindMode) ?? ("127.0.0.1", "127.0.0.1")
      services[index].state = .external
      services[index].statusText = "External service on port \(config.port)"
      services[index].pid = nil
      services[index].endpoint = Self.endpoint(id, config.port, hosts.display)
    } else if services[index].state != .failed {
      validatedProcessRoots[id] = .noOwnedPID(reason: "No launch record")
      processStore.remove(id)
      services[index].state = .stopped
      services[index].statusText = "Stopped"
      services[index].pid = nil
      services[index].endpoint = nil
    }
  }

  private func appendLog(_ id: ServiceID, _ message: String) {
    logStore.append(message, to: id, handle: processController.outputHandles[id])
    if let index = services.firstIndex(where: { $0.id == id }) {
      services[index].logText = logStore.tail(id)
    }
  }

  func markLaunchFailure(at index: Int, message: String, guidance: String) {
    let id = services[index].id
    logger.record(.launchFailed, serviceID: id)
    appendLog(id, "ERROR: \(message) Guidance: \(guidance)")
    services[index].state = .failed
    services[index].statusText = message
    services[index].pid = nil
    presentedFailure = .init(
      serviceID: id, serviceName: services[index].definition.name, message: message,
      guidance: guidance, timestamp: Date(), logURL: logURL(id))
  }

  private func completeIntentionalStop(_ id: ServiceID) {
    processController.completeStop(for: id)
    processStore.remove(id)
    if let index = services.firstIndex(where: { $0.id == id }) {
      services[index].state = .stopped
      services[index].statusText = "Stopped"
      services[index].pid = nil
      services[index].endpoint = nil
    }
  }

  private func validate(_ record: ManagedProcessRecord) async -> Bool {
    let root = await ManagedProcessOwnership.root(record, probe: probe)
    validatedProcessRoots[record.serviceID] = root
    if case .owned = root { return true }
    return false
  }
}
