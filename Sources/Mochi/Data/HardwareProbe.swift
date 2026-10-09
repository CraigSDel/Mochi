import Foundation

enum HardwareProfileParser {
    static func parse(sysctl: [String: String], systemProfilerData: Data?, detectedAt: Date = Date()) -> HardwareProfile {
        let arm = sysctl["hw.optional.arm64"].flatMap(Int.init) == 1
        let architecture: HardwareArchitecture = arm ? .appleSilicon : (sysctl["hw.ncpu"] != nil ? .intel : .unknown)
        let profiler = jsonObject(systemProfilerData)
        let hardware = firstDictionary(in: profiler["SPHardwareDataType"])
        let displays = firstDictionary(in: profiler["SPDisplaysDataType"])
        let chipName = stringValue(hardware["chip"])
            ?? stringValue(hardware["chip_type"])
            ?? stringValue(hardware["cpu_type"])
        let modelIdentifier = sysctl["hw.model"] ?? stringValue(hardware["machine_model"])
        let memory = UInt64(sysctl["hw.memsize"] ?? "") ?? parseBytes(stringValue(hardware["physical_memory"])) ?? 0
        let cpu = Int(sysctl["hw.ncpu"] ?? "") ?? parseInteger(stringValue(hardware["number_processors"]))
        let performance = Int(sysctl["hw.perflevel0.physicalcpu"] ?? "")
        let efficiency = Int(sysctl["hw.perflevel1.physicalcpu"] ?? "")
        let gpu = parseInteger(
            stringValue(displays["spdisplays_total_cores"])
                ?? stringValue(displays["sppci_cores"])
                ?? stringValue(displays["gpu_cores"])
        )
        let family = chipFamily(chipName)
        var missing = [String]()
        if architecture == .unknown { missing.append("architecture") }
        if memory == 0 { missing.append("physical memory") }
        if chipName == nil && architecture == .appleSilicon { missing.append("chip name") }
        if cpu == nil { missing.append("CPU cores") }
        if gpu == nil { missing.append("GPU cores") }
        return .init(architecture: architecture, modelIdentifier: modelIdentifier, chipName: chipName, chipFamily: family.0, chipGeneration: family.1, physicalMemory: memory, cpuCoreCount: cpu, performanceCoreCount: performance, efficiencyCoreCount: efficiency, gpuCoreCount: gpu, detectedAt: detectedAt, unavailableFields: missing)
    }

    private static func jsonObject(_ data: Data?) -> [String: Any] {
        guard let data, let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return object
    }

    private static func firstDictionary(in value: Any?) -> [String: Any] {
        if let array = value as? [[String: Any]] { return array.first ?? [:] }
        return [:]
    }

    private static func stringValue(_ value: Any?) -> String? {
        if let value = value as? String { return value }
        if let value = value as? NSNumber { return value.stringValue }
        return nil
    }

    private static func parseInteger(_ value: String?) -> Int? {
        guard let value else { return nil }
        guard let range = value.range(of: #"\d+"#, options: .regularExpression) else { return nil }
        return Int(value[range])
    }

    private static func parseBytes(_ value: String?) -> UInt64? {
        guard let value, let number = Double(value.filter { $0.isNumber || $0 == "." }) else { return nil }
        let lower = value.lowercased()
        let multiplier: Double = lower.contains("tb") ? 1_099_511_627_776 : lower.contains("gb") ? 1_073_741_824 : lower.contains("mb") ? 1_048_576 : 1
        return UInt64(number * multiplier)
    }

    private static func chipFamily(_ chip: String?) -> (String?, Int?) {
        guard let chip else { return (nil, nil) }
        let match = chip.range(of: #"M[0-9]+"#, options: .regularExpression)
        guard let match else { return (chip, nil) }
        let token = String(chip[match]); return (token, Int(token.dropFirst()))
    }
}

extension LiveSystemProbe {
    func hardwareProfile() async -> HardwareProfile {
        let keys = ["hw.optional.arm64", "hw.memsize", "hw.ncpu", "hw.perflevel0.physicalcpu", "hw.perflevel1.physicalcpu", "hw.model"]
        var values: [String: String] = [:]
        for key in keys { values[key] = await runCommand("/usr/sbin/sysctl", arguments: ["-n", key]) ?? "" }
        let profiler = await runCommand("/usr/sbin/system_profiler", arguments: ["SPHardwareDataType", "SPDisplaysDataType", "-json"])
        return HardwareProfileParser.parse(sysctl: values, systemProfilerData: profiler?.data(using: .utf8))
    }

    private func runCommand(_ executable: String, arguments: [String]) async -> String? {
        guard fileManager.isExecutableFile(atPath: executable) else { return nil }
        return await Self.runDetached(executable, arguments)
    }
}
