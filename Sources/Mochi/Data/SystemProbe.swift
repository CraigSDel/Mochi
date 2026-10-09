import Darwin
import Foundation
import SystemConfiguration

protocol SystemCommandProbing: AnyObject, Sendable {
  func commandPath(_ command: String) async -> String?
}

protocol NetworkProbing: AnyObject, Sendable {
  func tailscaleIP() async -> String?
  func wifiIP() async -> String?
  func localNetworkIP() async -> String?
}

protocol ProcessProbing: AnyObject, Sendable {
  func isProcessRunning(_ pid: Int32) async -> Bool
  func processCommand(_ pid: Int32) async -> String
}

protocol RuntimeHealthProbing: AnyObject, Sendable {
  func isPortListening(_ port: Int) async -> Bool
  func healthResponding(_ id: ServiceID, port: Int, host: String) async -> Bool
}

protocol RuntimeResourceProbing: AnyObject, Sendable {
  var supportDirectory: URL { get }
  var physicalMemory: UInt64 { get }
  func availableDiskBytes() async -> Int64
  func scriptURL(named name: String) async -> URL?
}

protocol ModelInventoryProbing: AnyObject, Sendable {
  func discoverModels() async -> [DiscoveredModel]
}

protocol HardwareProbing: AnyObject, Sendable {
  func hardwareProfile() async -> HardwareProfile
}

protocol SystemProbing: SystemCommandProbing, NetworkProbing, ProcessProbing,
  RuntimeHealthProbing, RuntimeResourceProbing, ModelInventoryProbing, HardwareProbing
{
  func tailscaleDiagnostic() async -> TailscaleDiagnostic
}

final class LiveSystemProbe: SystemProbing, @unchecked Sendable {
  let fileManager: FileManager
  init(fileManager: FileManager = .default) { self.fileManager = fileManager }
  var supportDirectory: URL {
    fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("Mochi")
  }
  var physicalMemory: UInt64 { ProcessInfo.processInfo.physicalMemory }
  func commandPath(_ command: String) async -> String? {
    guard !command.isEmpty else { return nil }
    for directory in ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"] {
      let candidate = URL(fileURLWithPath: directory).appendingPathComponent(command).path
      if fileManager.isExecutableFile(atPath: candidate) { return candidate }
    }
    return nil
  }
  func isPortListening(_ port: Int) async -> Bool {
    !(await run("/usr/sbin/lsof", ["-nP", "-tiTCP:\(port)", "-sTCP:LISTEN"]) ?? "").isEmpty
  }
  func tailscaleIP() async -> String? {
    guard let executable = await commandPath("tailscale") else { return nil }
    return await run(executable, ["ip", "-4"])?.split(separator: "\n").first.map(String.init)
  }
  func wifiIP() async -> String? {
    await Task.detached(priority: .utility) { Self.liveWiFiIP() }.value
  }

  private nonisolated static func liveWiFiIP() -> String? {
    let interfaces = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] ?? []
    for interface in interfaces {
      guard let interfaceType = SCNetworkInterfaceGetInterfaceType(interface),
        CFEqual(interfaceType, kSCNetworkInterfaceTypeIEEE80211),
        let name = SCNetworkInterfaceGetBSDName(interface) as String?,
        let address = interfaceIPv4(named: name)
      else { continue }
      return address
    }
    return nil
  }
  func localNetworkIP() async -> String? {
    if let wifi = await wifiIP() { return wifi }
    return await Task.detached(priority: .utility) { Self.interfaceIPv4(named: nil) }.value
  }
  private nonisolated static func interfaceIPv4(named requiredName: String?) -> String? {
    var interfaces: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&interfaces) == 0, let first = interfaces else { return nil }
    defer { freeifaddrs(interfaces) }
    for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
      let interface = pointer.pointee
      guard let address = interface.ifa_addr, address.pointee.sa_family == UInt8(AF_INET) else {
        continue
      }
      let name = String(cString: interface.ifa_name)
      if let requiredName, name != requiredName { continue }
      if requiredName == nil && ["utun", "ipsec", "ppp"].contains(where: name.hasPrefix) {
        continue
      }
      let flags = Int32(interface.ifa_flags)
      guard flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0 else { continue }
      var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
      let result = getnameinfo(
        address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count), nil, 0,
        NI_NUMERICHOST)
      if result == 0 {
        return String(
          decoding: host.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
      }
    }
    return nil
  }
  func availableDiskBytes() async -> Int64 {
    guard
      let value = try? supportDirectory.deletingLastPathComponent().resourceValues(forKeys: [
        .volumeAvailableCapacityForImportantUsageKey
      ]).volumeAvailableCapacityForImportantUsage
    else { return 0 }
    return Int64(value)
  }
  func scriptURL(named name: String) async -> URL? {
    if let url = Bundle.main.resourceURL?.appendingPathComponent(name),
      fileManager.fileExists(atPath: url.path)
    {
      return url
    }
    let local = URL(fileURLWithPath: fileManager.currentDirectoryPath).appendingPathComponent(name)
    return fileManager.fileExists(atPath: local.path) ? local : nil
  }
  func isProcessRunning(_ pid: Int32) async -> Bool {
    await Task.detached(priority: .utility) { kill(pid, 0) == 0 }.value
  }
  func processCommand(_ pid: Int32) async -> String {
    await run("/bin/ps", ["-p", String(pid), "-o", "command="]) ?? ""
  }
  func healthResponding(_ id: ServiceID, port: Int, host: String) async -> Bool {
    guard let url = URL(string: "http://\(host):\(port)/health") else { return false }
    var request = URLRequest(url: url)
    request.timeoutInterval = 1
    do {
      let (_, response) = try await URLSession.shared.data(for: request)
      return (200..<500).contains((response as? HTTPURLResponse)?.statusCode ?? 0)
    } catch { return false }
  }
  func discoverModels() async -> [DiscoveredModel] {
    await Task.detached(priority: .utility) { [fileManager] in
      ModelInventoryScanner(fileManager: fileManager).scan()
    }.value
  }
  private func run(_ executable: String, _ arguments: [String]) async -> String? {
    let isExecutable = fileManager.isExecutableFile(atPath: executable)
    guard isExecutable else { return nil }
    return await Self.runDetached(executable, arguments)
  }

  nonisolated static func runDetached(_ executable: String, _ arguments: [String]) async -> String?
  {
    await Task.detached(priority: .utility) {
      let process = Process()
      let pipe = Pipe()
      process.executableURL = URL(fileURLWithPath: executable)
      process.arguments = arguments
      process.standardOutput = pipe
      process.standardError = FileHandle.nullDevice
      do { try process.run() } catch { return nil }
      let data = pipe.fileHandleForReading.readDataToEndOfFile()
      process.waitUntilExit()
      guard process.terminationStatus == 0 else { return nil }
      return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }.value
  }
}

@MainActor protocol ProcessMaking: AnyObject { func makeProcess() -> Process }
@MainActor final class LiveProcessFactory: ProcessMaking {
  func makeProcess() -> Process { Process() }
}
