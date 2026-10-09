import Foundation

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

enum SystemMemoryAccounting {
  static func usedBytes(
    physicalMemory: UInt64,
    pageSize: UInt64,
    freePages: UInt64,
    inactivePages: UInt64,
    speculativePages: UInt64
  ) -> UInt64 {
    let reclaimablePages = [freePages, inactivePages, speculativePages].reduce(UInt64(0)) {
      let (sum, overflow) = $0.addingReportingOverflow($1)
      return overflow ? .max : sum
    }
    let (reclaimableBytes, overflow) = reclaimablePages.multipliedReportingOverflow(by: pageSize)
    let boundedReclaimableBytes = min(overflow ? UInt64.max : reclaimableBytes, physicalMemory)
    return physicalMemory - boundedReclaimableBytes
  }
}

enum ProcessTreeMemory {
  static func aggregate(
    rootPID: Int32,
    footprint: (Int32) -> UInt64?,
    children: (Int32) -> [Int32]
  ) -> UInt64? {
    var pending = [rootPID]
    var visited = Set<Int32>()
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
