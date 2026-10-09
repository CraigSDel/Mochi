import Foundation

@MainActor
extension ServiceManager {
    func startAll(warningsAcknowledged: Bool = false, bindModeOverride: BindMode? = nil) async {
        let ids = Self.startAllServiceIDs
        guard validationIssuesForStartAll().isEmpty,
              warningsAcknowledged || launchWarnings(for: ids, bindModeOverride: bindModeOverride).isEmpty else { return }
        for id in ids {
            await start(id, warningsAcknowledged: warningsAcknowledged, bindModeOverride: bindModeOverride, overrideSavedMode: true)
        }
    }

    func stopAll() async {
        for id in ServiceID.allCases { await stop(id) }
    }

    func start(
        _ id: ServiceID,
        warningsAcknowledged: Bool = false,
        bindModeOverride: BindMode? = nil,
        overrideSavedMode: Bool = false
    ) async {
        guard let index = services.firstIndex(where: { $0.id == id }) else { return }
        logger.record(.launchAttempt, serviceID: id)
        let savedConfig = configuration(for: id)
        var config = savedConfig
        config.bindMode = Self.effectiveBindMode(configured: savedConfig.bindMode, override: bindModeOverride, overrideSavedMode: overrideSavedMode)
        guard validationIssues(for: id).isEmpty else {
            markLaunchFailure(at: index, message: "Launch configuration is invalid.", guidance: "Correct the highlighted fields and retry.")
            return
        }
        guard warningsAcknowledged || launchWarnings(for: [id]).isEmpty else {
            markLaunchFailure(at: index, message: "Launch confirmation is required.", guidance: "Review and acknowledge the network or custom-model warning.")
            return
        }
        prepareLaunchState(at: index, id: id, saved: savedConfig, effective: config)
        guard await runLaunchPreflight(id: id, index: index, config: config) else { return }
        guard let process = createProcess(id: id, index: index, config: config) else { return }
        await finishLaunch(id: id, index: index, config: config, process: process)
    }

    private func prepareLaunchState(at index: Int, id: ServiceID, saved: ServiceLaunchConfiguration, effective: ServiceLaunchConfiguration) {
        appendLaunchLog(id, "========== START ATTEMPT ==========")
        let overrideNote = effective.bindMode != saved.bindMode ? " (one-time override from \(saved.bindMode.title))" : ""
        appendLaunchLog(id, "Mode: \(effective.downloadPolicy.title); bind: \(effective.bindMode.title)\(overrideNote); port: \(effective.port)")
        services[index].state = .starting
        services[index].statusText = "Running preflight checks…"
        presentedFailure = nil
    }

    private func runLaunchPreflight(id: ServiceID, index: Int, config: ServiceLaunchConfiguration) async -> Bool {
        let definition = services[index].definition
        let occupied = await probe.isPortListening(config.port)
        appendLaunchLog(id, "Port \(config.port): \(occupied ? "occupied" : "available")")
        guard !occupied else {
            markLaunchFailure(at: index, message: "Port \(config.port) is already occupied.", guidance: "Stop the external service or choose another port.")
            return false
        }
        guard let executable = await probe.commandPath(definition.executable ?? "") else {
            markLaunchFailure(at: index, message: "\(definition.executable ?? definition.runtime) is not installed.", guidance: "Install llama.cpp and make sure llama-server is available on PATH.")
            return false
        }
        appendLaunchLog(id, "Runtime executable: \(executable)")
        let assessment = memoryAssessment(for: id)
        appendLaunchLog(id, "Memory assessment: \(assessment.severity.rawValue); \(assessment.message)")
        if config.bindMode == .tailscale {
            guard await probe.commandPath("tailscale") != nil else {
                markLaunchFailure(at: index, message: "Tailscale is not installed.", guidance: "Run: brew install tailscale")
                return false
            }
            guard await probe.tailscaleIP() != nil else {
                markLaunchFailure(at: index, message: "Tailscale is not connected.", guidance: "Connect Tailscale outside the app, then retry.")
                return false
            }
        }
        guard let hosts = await resolvedHosts(for: config.bindMode) else {
            let message = config.bindMode == .tailscale ? "Tailscale is not installed or connected." : "A local network IPv4 address could not be resolved."
            let guidance = config.bindMode == .tailscale ? "Install and connect Tailscale, then retry." : "Connect this Mac to a local network, then retry."
            markLaunchFailure(at: index, message: message, guidance: guidance)
            return false
        }
        appendLaunchLog(id, "Endpoint host: \(hosts.display); health host: \(hosts.health)")
        let disk = await probe.availableDiskBytes()
        appendLaunchLog(id, "Available disk: \(disk) bytes")
        guard disk >= 5_000_000_000 else {
            markLaunchFailure(at: index, message: "Less than 5 GB of free disk space is available.", guidance: "Free disk space, then retry.")
            return false
        }
        let scriptName = "start_llama_network.sh"
        guard let script = await probe.scriptURL(named: scriptName) else {
            markLaunchFailure(at: index, message: "Could not locate \(scriptName).", guidance: "Rebuild the app so launcher resources are bundled.")
            return false
        }
        launchHosts[id] = hosts
        launchScripts[id] = script
        return true
    }

    private func createProcess(id: ServiceID, index: Int, config: ServiceLaunchConfiguration) -> Process? {
        guard let script = launchScripts.removeValue(forKey: id), let hosts = launchHosts.removeValue(forKey: id) else {
            markLaunchFailure(at: index, message: "Could not prepare the service launcher.", guidance: "Retry the launch.")
            return nil
        }
        do {
            let handle = try logStore.openForAppending(id)
            let process = processController.makeProcess(for: id, output: handle) { [weak self] ended in
                Task { @MainActor in self?.handleTermination(id, status: ended.terminationStatus, reason: ended.terminationReason) }
            }
            let definition = services[index].definition
            process.arguments = LaunchInvocation.arguments(id: id, script: script, modelChoice: definition.modelChoice, configuration: config)
            process.environment = LaunchInvocation.environment(id: id, configuration: config, modelSettings: modelSettings(for: id))
            appendLaunchLog(id, "Launcher: /bin/bash \(process.arguments?.joined(separator: " ") ?? "")")
            launchHosts[id] = hosts
            return process
        } catch {
            markLaunchFailure(at: index, message: "Could not open the service log.", guidance: error.localizedDescription)
            return nil
        }
    }

    private func finishLaunch(id: ServiceID, index: Int, config: ServiceLaunchConfiguration, process: Process) async {
        do {
            try process.run()
            processController.register(process, for: id)
            logger.record(.launchStarted(pid: process.processIdentifier), serviceID: id)
            appendLaunchLog(id, "Process started with PID \(process.processIdentifier)")
            let identity = ["/bin/bash"] + (process.arguments ?? [])
            let record = ManagedProcessRecord(serviceID: id, pid: process.processIdentifier, port: config.port, expectedCommand: identity.joined(separator: " "), runtimeCommand: nil, startedAt: Date(), logPath: logURL(id).path, bindMode: config.bindMode)
            save(record)
            services[index].pid = process.processIdentifier
            let displayHost = launchHosts.removeValue(forKey: id)?.display ?? "127.0.0.1"
            services[index].endpoint = Self.endpoint(id, config.port, displayHost)
            try? await Task.sleep(for: .seconds(1))
            await captureRuntimeIdentity(for: record)
            await refreshStatuses()
        } catch {
            processController.closeOutput(for: id)
            launchHosts.removeValue(forKey: id)
            markLaunchFailure(at: index, message: "Failed to launch the service.", guidance: error.localizedDescription)
        }
    }

    private func appendLaunchLog(_ id: ServiceID, _ message: String) {
        logStore.append(message, to: id, handle: processController.outputHandles[id])
        if let index = services.firstIndex(where: { $0.id == id }) { services[index].logText = logStore.tail(id) }
    }

    private func handleTermination(_ id: ServiceID, status: Int32, reason: Process.TerminationReason) {
        guard let index = services.firstIndex(where: { $0.id == id }) else { return }
        logger.record(.processTerminated(status: status), serviceID: id)
        appendLaunchLog(id, "Process terminated; status=\(status), reason=\(reason.rawValue)")
        processController.closeOutput(for: id)
        processController.removeProcess(for: id)
        if processController.wasStopRequested(for: id) || services[index].state == .stopping {
            completeLaunchStop(id)
        } else {
            processStore.remove(id)
            markLaunchFailure(at: index, message: "Service exited unexpectedly (status \(status)).", guidance: "Review the log for the runtime error.")
        }
    }
    private func completeLaunchStop(_ id: ServiceID) {
        processController.completeStop(for: id)
        processStore.remove(id)
        if let index = services.firstIndex(where: { $0.id == id }) {
            services[index].state = .stopped
            services[index].statusText = "Stopped"
            services[index].pid = nil
            services[index].endpoint = nil
        }
    }
}
