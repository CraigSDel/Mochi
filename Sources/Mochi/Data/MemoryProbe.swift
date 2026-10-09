import Darwin
import Foundation

protocol MemoryProbing: AnyObject, Sendable {
  func systemMemory() async -> SystemMemoryReading?
  func processTreePhysicalFootprint(rootPID: Int32) async -> UInt64?
}

/// Stateless system calls are isolated in detached utility tasks, so this
/// implementation can safely cross the actor boundary required by the probe.
final class LiveMemoryProbe: MemoryProbing, @unchecked Sendable {
  func systemMemory() async -> SystemMemoryReading? {
    await Task.detached(priority: .utility) {
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

      let total = ProcessInfo.processInfo.physicalMemory
      let used = SystemMemoryAccounting.usedBytes(
        physicalMemory: total,
        pageSize: UInt64(getpagesize()),
        freePages: UInt64(statistics.free_count),
        inactivePages: UInt64(statistics.inactive_count),
        speculativePages: UInt64(statistics.speculative_count)
      )
      return SystemMemoryReading(usedBytes: used, totalBytes: total)
    }.value
  }

  func processTreePhysicalFootprint(rootPID: Int32) async -> UInt64? {
    guard rootPID > 0 else { return nil }
    return await Task.detached(priority: .utility) {
      ProcessTreeMemory.aggregate(
        rootPID: rootPID,
        footprint: Self.physicalFootprint,
        children: Self.childPIDs
      )
    }.value
  }

  private static func physicalFootprint(_ pid: Int32) -> UInt64? {
    var info = rusage_info_v4()
    let result = withUnsafeMutablePointer(to: &info) { pointer in
      pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
        proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
      }
    }
    return result == 0 ? info.ri_phys_footprint : nil
  }

  private static func childPIDs(_ pid: Int32) -> [Int32] {
    var children = [Int32](repeating: 0, count: 64)
    let byteCount = Int32(children.count * MemoryLayout<Int32>.stride)
    let count = children.withUnsafeMutableBytes {
      proc_listchildpids(pid, $0.baseAddress, byteCount)
    }
    guard count > 0 else { return [] }
    return Array(children.prefix(Int(count))).filter { $0 > 0 }
  }
}
