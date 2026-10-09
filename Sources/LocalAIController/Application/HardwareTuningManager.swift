import Foundation

extension ServiceManager {
    func updateRecommendationMetadata(_ recommendations: [ModelRecommendation]) {
        recommendationMetadata = recommendations
        rebuildHardwareTuningPlan()
    }

    func refreshHardwareProfile() async {
        guard !isRefreshingHardware else { return }
        isRefreshingHardware = true
        let profile = await probe.hardwareProfile()
        hardwareProfile = profile
        rebuildHardwareTuningPlan()
        isRefreshingHardware = false
    }

    func applyHardwareTuning() {
        guard let plan = hardwareTuningPlan, plan.hasConfigurationChanges else {
            hardwareApplyMessage = "The current configuration is already within the safe hardware profile."
            return
        }
        var previous: [ServiceID: ServiceLaunchConfiguration] = [:]
        var applied = 0
        var skipped = 0
        for (id, tuned) in plan.configurations {
            guard !isConfigurationLocked(id) else { skipped += 1; continue }
            previous[id] = configuration(for: id)
            configurations[id] = tuned
            applied += 1
        }
        guard !previous.isEmpty else {
            hardwareApplyMessage = "No settings changed because all affected services are active."
            return
        }
        if let data = try? JSONEncoder().encode(previous) { defaults.set(data, forKey: hardwareUndoKey) }
        canRestoreHardwareTuning = true
        persistConfigurations()
        let appliedLabel = applied == 1 ? "service" : "services"
        let skippedLabel = skipped == 1 ? "service was" : "services were"
        hardwareApplyMessage = "Applied safe tuning to \(applied) \(appliedLabel)." + (skipped == 0 ? "" : " \(skipped) active \(skippedLabel) skipped.")
        rebuildHardwareTuningPlan()
    }

    func restoreHardwareTuning() {
        guard let data = defaults.data(forKey: hardwareUndoKey), let previous = try? JSONDecoder().decode([ServiceID: ServiceLaunchConfiguration].self, from: data) else {
            canRestoreHardwareTuning = false
            hardwareApplyMessage = "There are no previous hardware-tuned settings to restore."
            return
        }
        var restored = 0
        for (id, configuration) in previous where !isConfigurationLocked(id) {
            configurations[id] = configuration
            restored += 1
        }
        defaults.removeObject(forKey: hardwareUndoKey)
        canRestoreHardwareTuning = false
        persistConfigurations()
        hardwareApplyMessage = "Restored \(restored) service configuration\(restored == 1 ? "" : "s")."
        rebuildHardwareTuningPlan()
    }

    func rebuildHardwareTuningPlan() {
        guard let hardwareProfile else { return }
        hardwareTuningPlan = HardwareTuningPolicy.plan(profile: hardwareProfile, configurations: configurations, installedModels: installedModels, recommendations: recommendationMetadata)
    }
}
