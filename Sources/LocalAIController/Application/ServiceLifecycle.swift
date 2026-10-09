import Foundation
import Darwin

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
        for id in [ServiceID.llamaChat, .autocomplete, .embeddings, .ollama] { await stop(id) }
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
        config.bindMode = Self.effectiveBindMode(
            configured: savedConfig.bindMode,
            override: bindModeOverride,
            overrideSavedMode: overrideSavedMode
        )
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

    private func prepareLaunchState(
        at index: Int,
        id: ServiceID,
        saved: ServiceLaunchConfiguration,
        effective: ServiceLaunchConfiguration
    ) {
        appendLog(id, "========== START ATTEMPT ==========")
        let overrideNote = effective.bindMode != saved.bindMode ? " (one-time override from \(saved.bindMode.title))" : ""
        appendLog(id, "Mode: \(effective.downloadPolicy.title); bind: \(effective.bindMode.title)\(overrideNote); port: \(effective.port)")
        services[index].state = .starting
        services[index].statusText = "Running preflight checks…"
        presentedFailure = nil
    }

    private func runLaunchPreflight(id: ServiceID, index: Int, config: ServiceLaunchConfiguration) async -> Bool {
        let definition = services[index].definition
        let occupied = await probe.isPortListening(config.port)
        appendLog(id, "Port \(config.port): \(occupied ? "occupied" : "available")")
        guard !occupied else {
            markLaunchFailure(at: index, message: "Port \(config.port) is already occupied.", guidance: "Stop the external service or choose another port.")
            return false
        }
        guard let executable = await probe.commandPath(definition.executable ?? "") else {
            markLaunchFailure(at: index, message: "\(definition.executable ?? definition.runtime) is not installed.", guidance: "Run: brew install \(id == .ollama ? "ollama" : "llama.cpp")")
            return false
        }
        appendLog(id, "Runtime executable: \(executable)")
        let assessment = memoryAssessment(for: id)
        appendLog(id, "Memory assessment: \(assessment.severity.rawValue); \(assessment.message)")
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
        appendLog(id, "Endpoint host: \(hosts.display); health host: \(hosts.health)")
        let disk = await probe.availableDiskBytes()
        appendLog(id, "Available disk: \(disk) bytes")
        guard disk >= 5_000_000_000 else {
            markLaunchFailure(at: index, message: "Less than 5 GB of free disk space is available.", guidance: "Free disk space, then retry.")
            return false
        }
        let scriptName = id == .ollama ? "start_ollama_network.sh" : "start_llama_network.sh"
        guard let script = await probe.scriptURL(named: scriptName) else {
            markLaunchFailure(at: index, message: "Could not locate \(scriptName).", guidance: "Rebuild the app so launcher resources are bundled.")
            return false
        }
        launchHosts[id] = hosts
        launchScripts[id] = script
        return true
    }

    private func createProcess(id: ServiceID, index: Int, config: ServiceLaunchConfiguration) -> Process? {
        guard let script = launchScripts.removeValue(forKey: id),
              let hosts = launchHosts.removeValue(forKey: id) else {
            markLaunchFailure(at: index, message: "Could not prepare the service launcher.", guidance: "Retry the launch.")
            return nil
        }
        do {
            let handle = try logStore.openForAppending(id)
            let process = processController.makeProcess(for: id, output: handle) { [weak self] ended in
                Task { @MainActor in
                    self?.handleTermination(id, status: ended.terminationStatus, reason: ended.terminationReason)
                }
            }
            let definition = services[index].definition
            process.arguments = LaunchInvocation.arguments(id: id, script: script, modelChoice: definition.modelChoice, configuration: config)
            process.environment = LaunchInvocation.environment(id: id, configuration: config, modelSettings: modelSettings(for: id))
            appendLog(id, "Launcher: /bin/bash \(process.arguments?.joined(separator: " ") ?? "")")
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
            appendLog(id, "Process started with PID \(process.processIdentifier)")
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

    func stop(_ id: ServiceID) async {
        guard let index = services.firstIndex(where: { $0.id == id }),
              let record = processStore.load(id),
              await validate(record) else {
            logger.record(.ownershipRejected, serviceID: id)
            if let index = services.firstIndex(where: { $0.id == id }), services[index].state == .external {
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
                let hosts = await resolvedHosts(for: record.bindMode ?? .tailscale) ?? ("127.0.0.1", "127.0.0.1")
                let listening = await probe.isPortListening(record.port)
                let healthy = listening ? await probe.healthResponding(id, port: record.port, host: hosts.health) : false
                let endpoint = Self.endpoint(id, record.port, hosts.display)
                services[index].state = healthy ? .running : .starting
                services[index].statusText = healthy ? "Running and healthy at \(endpoint)" : "Process active; waiting for health"
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
        if let index = services.firstIndex(where: { $0.id == id }) { services[index].logText = logStore.tail(id) }
    }

    func markLaunchFailure(at index: Int, message: String, guidance: String) {
        let id = services[index].id
        logger.record(.launchFailed, serviceID: id)
        appendLog(id, "ERROR: \(message) Guidance: \(guidance)")
        services[index].state = .failed
        services[index].statusText = message
        services[index].pid = nil
        presentedFailure = .init(serviceID: id, serviceName: services[index].definition.name, message: message, guidance: guidance, timestamp: Date(), logURL: logURL(id))
    }

    private func handleTermination(_ id: ServiceID, status: Int32, reason: Process.TerminationReason) {
        guard let index = services.firstIndex(where: { $0.id == id }) else { return }
        logger.record(.processTerminated(status: status), serviceID: id)
        appendLog(id, "Process terminated; status=\(status), reason=\(reason.rawValue)")
        processController.closeOutput(for: id)
        processController.removeProcess(for: id)
        if processController.wasStopRequested(for: id) || services[index].state == .stopping {
            completeIntentionalStop(id)
        } else {
            processStore.remove(id)
            markLaunchFailure(at: index, message: "Service exited unexpectedly (status \(status)).", guidance: "Review the log for the runtime error.")
        }
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
