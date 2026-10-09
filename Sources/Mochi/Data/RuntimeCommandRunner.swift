import Foundation

protocol RuntimeCommandRunning: Sendable {
  func run(_ command: String, arguments: [String]) async throws
}

final class LiveRuntimeCommandRunner: RuntimeCommandRunning, @unchecked Sendable {
  private let fileManager: FileManager

  init(fileManager: FileManager = .default) {
    self.fileManager = fileManager
  }

  func run(_ command: String, arguments: [String]) async throws {
    guard
      let executable = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"]
        .lazy
        .map({ URL(fileURLWithPath: $0).appendingPathComponent(command).path })
        .first(where: { fileManager.isExecutableFile(atPath: $0) })
    else {
      throw ModelManagementError.runtimeUnavailable(command)
    }
    let cancellation = ProcessCancellationBox()
    let result = await withTaskCancellationHandler {
      await Task.detached(priority: .utility) {
        let process = Process()
        let pipe = Pipe()
        cancellation.set(process)
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe
        do { try process.run() } catch { return (1, error.localizedDescription) }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (Int(process.terminationStatus), String(data: data, encoding: .utf8) ?? "")
      }.value
    } onCancel: {
      cancellation.terminate()
    }
    try Task.checkCancellation()
    guard result.0 == 0 else {
      throw ModelManagementError.commandFailed(
        result.1.trimmingCharacters(in: .whitespacesAndNewlines))
    }
  }
}

private final class ProcessCancellationBox: @unchecked Sendable {
  private let lock = NSLock()
  private var process: Process?

  func set(_ process: Process) {
    lock.lock()
    self.process = process
    lock.unlock()
  }

  func terminate() {
    lock.lock()
    process?.terminate()
    lock.unlock()
  }
}
