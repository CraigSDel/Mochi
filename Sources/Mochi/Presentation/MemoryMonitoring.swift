import Combine
import Foundation

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

  init(
    timestamp: Date, systemUsedBytes: UInt64, systemTotalBytes: UInt64,
    serviceReadings: [ServiceID: ServiceMemoryReading]
  ) {
    self.timestamp = timestamp
    self.systemUsedBytes = systemUsedBytes
    self.systemTotalBytes = systemTotalBytes
    self.serviceReadings = serviceReadings
  }

  init(
    timestamp: Date, systemUsedBytes: UInt64, systemTotalBytes: UInt64,
    serviceBytes: [ServiceID: UInt64]
  ) {
    self.init(
      timestamp: timestamp,
      systemUsedBytes: systemUsedBytes,
      systemTotalBytes: systemTotalBytes,
      serviceReadings: Dictionary(
        uniqueKeysWithValues: ServiceID.allCases.map { id in
          (
            id,
            serviceBytes[id].map(ServiceMemoryReading.measured)
              ?? .noOwnedPID(reason: "No owned PID")
          )
        })
    )
  }
}

@MainActor
final class MemoryMonitor: ObservableObject {
  @Published private(set) var samples: [MemorySample] = []
  var currentSample: MemorySample? { samples.last }

  private let probe: any MemoryProbing
  private let maximumSampleCount: Int
  private let wakeNotificationSource: any WakeNotificationSource
  private var timer: Timer?
  private var wakeNotificationToken: NSObjectProtocol?
  private var serviceRootProvider: (() -> [ServiceID: ManagedProcessRoot])?

  init(
    probe: any MemoryProbing = LiveMemoryProbe(),
    maximumSampleCount: Int = PerformanceBudgets.maximumMemorySamples,
    wakeNotificationSource: (any WakeNotificationSource)? = nil,
    wakeNotificationCenter: NotificationCenter? = nil
  ) {
    self.probe = probe
    self.maximumSampleCount = max(1, maximumSampleCount)
    self.wakeNotificationSource =
      wakeNotificationSource
      ?? wakeNotificationCenter.map { NotificationCenterWakeSource(center: $0) }
      ?? LiveWakeNotificationSource()
  }

  func start(serviceRoots: @escaping () -> [ServiceID: ManagedProcessRoot]) async {
    serviceRootProvider = serviceRoots
    await captureOwnedRoots()
    guard timer == nil else { return }
    installWakeObserver()
    timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
      Task { @MainActor in await self?.captureOwnedRoots() }
    }
  }

  func stop() {
    timer?.invalidate()
    timer = nil
    if let wakeNotificationToken {
      wakeNotificationSource.center.removeObserver(wakeNotificationToken)
      self.wakeNotificationToken = nil
    }
    serviceRootProvider = nil
  }

  private func captureOwnedRoots(at timestamp: Date = Date()) async {
    await capture(at: timestamp, serviceRoots: serviceRootProvider?() ?? [:])
  }

  private func installWakeObserver() {
    guard wakeNotificationToken == nil else { return }
    wakeNotificationToken = wakeNotificationSource.center.addObserver(
      forName: wakeNotificationSource.name,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor in await self?.captureOwnedRoots() }
    }
  }

  func capture(at timestamp: Date = Date(), serviceRoots: [ServiceID: ManagedProcessRoot]) async {
    guard let system = await probe.systemMemory() else { return }
    var readings: [ServiceID: ServiceMemoryReading] = [:]
    for id in ServiceID.allCases {
      let reading: ServiceMemoryReading
      switch serviceRoots[id] ?? .noOwnedPID(reason: "No ownership status available") {
      case .noOwnedPID(let reason):
        reading = .noOwnedPID(reason: reason)
      case .owned(let pid):
        if let bytes = await probe.processTreePhysicalFootprint(rootPID: pid) {
          reading = .measured(bytes: bytes)
        } else {
          reading = .footprintUnavailable(pid: pid)
        }
      }
      readings[id] = reading
    }
    samples.append(
      .init(
        timestamp: nextSampleTimestamp(after: timestamp),
        systemUsedBytes: system.usedBytes,
        systemTotalBytes: system.totalBytes,
        serviceReadings: readings
      ))
    if samples.count > maximumSampleCount {
      samples.removeFirst(samples.count - maximumSampleCount)
    }
  }

  private func nextSampleTimestamp(after timestamp: Date) -> Date {
    guard let previous = samples.last?.timestamp else { return timestamp }
    guard timestamp > previous else {
      return previous.addingTimeInterval(0.001)
    }
    return timestamp
  }
}
