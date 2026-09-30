import Foundation
import Combine
import Darwin

struct SystemMemoryReading: Equatable, Sendable {
    let usedBytes: UInt64
    let totalBytes: UInt64
}

enum ManagedProcessRoot: Equatable, Sendable {
    case noOwnedPID(reason: String)
    case owned(pid: Int32)
}

enum ServiceMemoryReading: Equatable, Sendable {
    case noOwnedPID(reason: String)
    case footprintUnavailable(pid: Int32)
    case measured(bytes: UInt64)

    var bytes: UInt64? {
        guard case .measured(let bytes) = self else { return nil }
        return bytes
    }
}

struct MemorySample: Identifiable, Equatable, Sendable {
    let timestamp: Date
    let systemUsedBytes: UInt64
    let systemTotalBytes: UInt64
    let serviceReadings: [ServiceID: ServiceMemoryReading]
    var id: Date { timestamp }
    var serviceBytes: [ServiceID: UInt64] {
        serviceReadings.compactMapValues(\.bytes)
    }
    var managedBytes: UInt64 {
        serviceBytes.values.reduce(0) { total, bytes in
            let (sum, overflow) = total.addingReportingOverflow(bytes)
            return overflow ? .max : sum
        }
    }

    init(timestamp: Date, systemUsedBytes: UInt64, systemTotalBytes: UInt64, serviceReadings: [ServiceID: ServiceMemoryReading]) {
        self.timestamp = timestamp
        self.systemUsedBytes = systemUsedBytes
        self.systemTotalBytes = systemTotalBytes
        self.serviceReadings = serviceReadings
    }

    init(timestamp: Date, systemUsedBytes: UInt64, systemTotalBytes: UInt64, serviceBytes: [ServiceID: UInt64]) {
        self.init(
            timestamp: timestamp,
            systemUsedBytes: systemUsedBytes,
            systemTotalBytes: systemTotalBytes,
            serviceReadings: Dictionary(uniqueKeysWithValues: ServiceID.allCases.map { id in
                (id, serviceBytes[id].map(ServiceMemoryReading.measured) ?? .noOwnedPID(reason: "No owned PID"))
            })
        )
    }
}

enum SystemMemoryAccounting {
    static func usedBytes(
        physicalMemory: UInt64,
        pageSize: UInt64,
        freePages: UInt64,
        inactivePages: UInt64,
        speculativePages: UInt64
    ) -> UInt64 {
        let reclaimablePages = [freePages, inactivePages, speculativePages].reduce(UInt64(0)) { total, pages in
            let (sum, overflow) = total.addingReportingOverflow(pages)
            return overflow ? .max : sum
        }
        let (reclaimableBytes, overflow) = reclaimablePages.multipliedReportingOverflow(by: pageSize)
        let boundedReclaimableBytes = min(overflow ? UInt64.max : reclaimableBytes, physicalMemory)
        return physicalMemory - boundedReclaimableBytes
    }
}

@MainActor
protocol MemoryProbing: AnyObject {
    func systemMemory() -> SystemMemoryReading?
    func processTreePhysicalFootprint(rootPID: Int32) -> UInt64?
}

extension LiveSystemProbe: MemoryProbing {
    func systemMemory() -> SystemMemoryReading? {
        var statistics = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size
        )
        let result = withUnsafeMutablePointer(to: &statistics) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let pageSize = UInt64(getpagesize())
        let total = physicalMemory
        let used = SystemMemoryAccounting.usedBytes(
            physicalMemory: total,
            pageSize: pageSize,
            freePages: UInt64(statistics.free_count),
            inactivePages: UInt64(statistics.inactive_count),
            speculativePages: UInt64(statistics.speculative_count)
        )
        return .init(usedBytes: used, totalBytes: total)
    }

    func processTreePhysicalFootprint(rootPID: Int32) -> UInt64? {
        guard rootPID > 0 else { return nil }
        return ProcessTreeMemory.aggregate(
            rootPID: pid_t(rootPID),
            footprint: physicalFootprint,
            children: childPIDs
        )
    }

    private func physicalFootprint(_ pid: pid_t) -> UInt64? {
        var info = rusage_info_v4()
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
            }
        }
        return result == 0 ? info.ri_phys_footprint : nil
    }

    private func childPIDs(_ pid: pid_t) -> [pid_t] {
        var children = [pid_t](repeating: 0, count: 64)
        let byteCount = Int32(children.count * MemoryLayout<pid_t>.stride)
        let count = children.withUnsafeMutableBytes {
            proc_listchildpids(pid, $0.baseAddress, byteCount)
        }
        guard count > 0 else { return [] }
        return Array(children.prefix(Int(count))).filter { $0 > 0 }
    }
}

enum ProcessTreeMemory {
    static func aggregate(
        rootPID: pid_t,
        footprint: (pid_t) -> UInt64?,
        children: (pid_t) -> [pid_t]
    ) -> UInt64? {
        var pending = [rootPID]
        var visited = Set<pid_t>()
        var total: UInt64 = 0
        var foundProcess = false
        while let pid = pending.popLast() {
            guard visited.insert(pid).inserted else { continue }
            if let bytes = footprint(pid) {
                total &+= bytes
                foundProcess = true
            }
            pending.append(contentsOf: children(pid).filter { !visited.contains($0) })
        }
        return foundProcess ? total : nil
    }
}

@MainActor
final class MemoryMonitor: ObservableObject {
    @Published private(set) var samples: [MemorySample] = []
    var currentSample: MemorySample? { samples.last }

    private let probe: any MemoryProbing
    private let maximumSampleCount: Int
    private var timer: Timer?
    private var serviceRootProvider: (() -> [ServiceID: ManagedProcessRoot])?

    init(probe: any MemoryProbing = LiveSystemProbe(), maximumSampleCount: Int = 900) {
        self.probe = probe
        self.maximumSampleCount = max(1, maximumSampleCount)
    }

    func start(servicePIDs: @escaping () -> [ServiceID: Int32]) {
        start(serviceRoots: {
            Dictionary(uniqueKeysWithValues: servicePIDs().map { ($0.key, .owned(pid: $0.value)) })
        })
    }

    func start(serviceRoots: @escaping () -> [ServiceID: ManagedProcessRoot]) {
        serviceRootProvider = serviceRoots
        captureOwnedRoots()
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.captureOwnedRoots() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        serviceRootProvider = nil
    }

    func capture(at timestamp: Date = Date(), servicePIDs: [ServiceID: Int32]? = nil) {
        let roots: [ServiceID: ManagedProcessRoot]
        if let servicePIDs {
            roots = Dictionary(uniqueKeysWithValues: ServiceID.allCases.map { id in
                (id, servicePIDs[id].map(ManagedProcessRoot.owned) ?? .noOwnedPID(reason: "No validated owned PID"))
            })
        } else {
            roots = serviceRootProvider?() ?? [:]
        }
        capture(at: timestamp, serviceRoots: roots)
    }

    private func captureOwnedRoots(at timestamp: Date = Date()) {
        capture(at: timestamp, serviceRoots: serviceRootProvider?() ?? [:])
    }

    private func capture(at timestamp: Date, serviceRoots: [ServiceID: ManagedProcessRoot]) {
        guard let system = probe.systemMemory() else { return }
        let readings = Dictionary(uniqueKeysWithValues: ServiceID.allCases.map { id in
            let reading: ServiceMemoryReading
            switch serviceRoots[id] ?? .noOwnedPID(reason: "No ownership status available") {
            case .noOwnedPID(let reason):
                reading = .noOwnedPID(reason: reason)
            case .owned(let pid):
                if let bytes = probe.processTreePhysicalFootprint(rootPID: pid) {
                    reading = .measured(bytes: bytes)
                } else {
                    reading = .footprintUnavailable(pid: pid)
                }
            }
            return (id, reading)
        })
        samples.append(.init(
            timestamp: timestamp,
            systemUsedBytes: system.usedBytes,
            systemTotalBytes: system.totalBytes,
            serviceReadings: readings
        ))
        if samples.count > maximumSampleCount {
            samples.removeFirst(samples.count - maximumSampleCount)
        }
    }
}
