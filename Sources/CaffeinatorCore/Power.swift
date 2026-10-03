import Darwin
import Foundation
import IOKit.pwr_mgt

public protocol PowerControl: AnyObject {
  func create(_ mode: Mode) throws -> UInt32
  func release(_ id: UInt32) throws
  func enableServer() throws
  func restoreServer() throws
  func recoveryNeeded() throws -> Bool
}

public struct ProcessResult {
  public var output: Data
  public var error: String
  public var status: Int32
}
public enum ProcessRunner {
  public static func run(_ executable: String, _ arguments: [String], timeout: TimeInterval = 15)
    throws -> ProcessResult
  {
    // Files avoid pipe-buffer deadlocks for ioreg and noisy command failures.
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(
      "caffeinator-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let outURL = dir.appendingPathComponent("stdout")
    let errURL = dir.appendingPathComponent("stderr")
    _ = FileManager.default.createFile(atPath: outURL.path, contents: nil)
    _ = FileManager.default.createFile(atPath: errURL.path, contents: nil)
    let out = try FileHandle(forWritingTo: outURL)
    let err = try FileHandle(forWritingTo: errURL)
    defer {
      try? out.close()
      try? err.close()
    }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.standardOutput = out
    process.standardError = err
    let done = DispatchSemaphore(value: 0)
    process.terminationHandler = { _ in done.signal() }
    try process.run()
    if done.wait(timeout: .now() + timeout) == .timedOut {
      process.terminate()
      if done.wait(timeout: .now() + 2) == .timedOut {
        Darwin.kill(process.processIdentifier, SIGKILL)
        _ = done.wait(timeout: .now() + 2)
      }
      throw AppError(
        "\(URL(fileURLWithPath: executable).lastPathComponent) timed out. Retry when ready.")
    }
    return ProcessResult(
      output: try Data(contentsOf: outURL),
      error: String(decoding: try Data(contentsOf: errURL), as: UTF8.self),
      status: process.terminationStatus)
  }
  public static func text(_ executable: String, _ arguments: [String]) throws -> String {
    let result = try run(executable, arguments)
    guard result.status == 0 else {
      throw AppError(result.error.trimmingCharacters(in: .whitespacesAndNewlines))
    }
    return String(decoding: result.output, as: UTF8.self)
  }
}

public struct RecoveryRecord: Codable {
  enum CodingKeys: String, CodingKey {
    case version
    case sleepDisabled = "sleep_disabled"
  }
  public var version: Int = 1
  public var sleepDisabled: Int
  public init(sleepDisabled: Int) { self.sleepDisabled = sleepDisabled }
}

public final class MacPower: PowerControl {
  private let directory: URL
  private let readOverride: (() throws -> Int)?
  private let writeOverride: ((Int) throws -> Void)?
  private var recoveryURL: URL { directory.appendingPathComponent("power-recovery.json") }
  public init(
    directory: URL = Storage.defaultDirectory, readOverride: (() throws -> Int)? = nil,
    writeOverride: ((Int) throws -> Void)? = nil
  ) {
    self.directory = directory
    self.readOverride = readOverride
    self.writeOverride = writeOverride
  }
  public func create(_ mode: Mode) throws -> UInt32 {
    var id: IOPMAssertionID = 0
    let result = IOPMAssertionCreateWithName(
      mode.assertionType as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn),
      "Caffeinator: \(mode.title)" as CFString, &id)
    guard result == kIOReturnSuccess else {
      throw AppError("Cannot create power assertion: \(result)")
    }
    return id
  }
  public func release(_ id: UInt32) throws {
    guard id != 0 else { return }
    let result = IOPMAssertionRelease(id)
    guard result == kIOReturnSuccess else {
      throw AppError("Cannot release power assertion: \(result)")
    }
  }
  private func recovery() throws -> RecoveryRecord? {
    guard FileManager.default.fileExists(atPath: recoveryURL.path) else { return nil }
    do {
      let record = try JSONDecoder().decode(
        RecoveryRecord.self, from: Data(contentsOf: recoveryURL))
      guard record.version == 1, (0...1).contains(record.sleepDisabled) else {
        throw AppError("Unsupported sleep recovery record")
      }
      return record
    } catch {
      throw AppError(
        "Cannot read sleep recovery record. Original settings are preserved: \(error.localizedDescription)"
      )
    }
  }
  public func recoveryNeeded() throws -> Bool { try recovery() != nil }
  private func sleepDisabled() throws -> Int {
    if let readOverride { return try readOverride() }
    let text = try ProcessRunner.text("/usr/bin/pmset", ["-g"])
    guard let value = PowerParser.value(text, key: "SleepDisabled"), (0...1).contains(value) else {
      throw AppError("macOS did not report its sleep override. Server Mode was not changed.")
    }
    return value
  }
  private func setSleepDisabled(_ value: Int) throws {
    guard (0...1).contains(value) else { throw AppError("Invalid sleep override") }
    if let writeOverride {
      try writeOverride(value)
      guard try sleepDisabled() == value else { throw AppError("Sleep override was not applied") }
      return
    }
    let script =
      "do shell script \"/usr/bin/pmset -a disablesleep \(value)\" with administrator privileges"
    let result = try ProcessRunner.run("/usr/bin/osascript", ["-e", script], timeout: 180)
    guard result.status == 0 else { throw AppError(Self.authorizationError(result.error)) }
    guard try sleepDisabled() == value else {
      throw AppError("macOS did not apply the requested setting. Retry restoration.")
    }
  }
  public static func authorizationError(_ stderr: String) -> String {
    let text = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
    return text.hasSuffix("(-128)")
      ? "Authorization canceled. Retry when you are ready."
      : "Could not change sleep settings: \(text)"
  }
  public func enableServer() throws {
    guard try !recoveryNeeded() else {
      throw AppError("Restore the previous Server Mode session first.")
    }
    let original = try sleepDisabled()
    try durableWrite(
      try JSONEncoder().encode(RecoveryRecord(sleepDisabled: original)), to: recoveryURL)
    if original != 1 {
      do { try setSleepDisabled(1) } catch {
        if !error.localizedDescription.contains("timed out"), (try? sleepDisabled()) == original {
          try? FileManager.default.removeItem(at: recoveryURL)
        }
        throw error
      }
    }
  }
  public func restoreServer() throws {
    guard let record = try recovery() else { return }
    if try sleepDisabled() != record.sleepDisabled { try setSleepDisabled(record.sleepDisabled) }
    try FileManager.default.removeItem(at: recoveryURL)
  }
}

func durableWrite(_ data: Data, to url: URL) throws {
  try FileManager.default.createDirectory(
    at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
  let temporary = url.appendingPathExtension("tmp")
  let fd = Darwin.open(temporary.path, O_WRONLY | O_CREAT | O_TRUNC | O_NOFOLLOW, S_IRUSR | S_IWUSR)
  guard fd >= 0 else { throw AppError("Cannot create recovery journal") }
  defer { Darwin.close(fd) }
  try data.withUnsafeBytes { bytes in
    var offset = 0
    while offset < bytes.count {
      let n = Darwin.write(fd, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
      if n < 0 && errno == EINTR { continue }
      guard n > 0 else { throw AppError("Cannot write recovery journal") }
      offset += n
    }
  }
  guard fsync(fd) == 0, rename(temporary.path, url.path) == 0 else {
    throw AppError("Cannot persist recovery journal")
  }
  let parent = Darwin.open(url.deletingLastPathComponent().path, O_RDONLY)
  guard parent >= 0 else { throw AppError("Cannot sync recovery directory") }
  defer { Darwin.close(parent) }
  guard fsync(parent) == 0 else { throw AppError("Cannot sync recovery directory") }
}

public enum PowerParser {
  public static func value(_ text: String, key: String) -> Int? {
    for line in text.split(separator: "\n") {
      let words = line.split(whereSeparator: { $0.isWhitespace })
      if words.first == Substring(key), words.count > 1 { return Int(words[1]) }
    }
    return nil
  }
  public static func preventedBy(_ text: String) -> [String] {
    for line in text.split(separator: "\n") {
      guard line.split(whereSeparator: { $0.isWhitespace }).first == "sleep",
        let start = line.range(of: "(sleep prevented by "),
        let end = line[start.upperBound...].firstIndex(of: ")")
      else { continue }
      return line[start.upperBound..<end].split(separator: ",").map {
        $0.trimmingCharacters(in: .whitespaces)
      }.filter { !$0.isEmpty }
    }
    return []
  }
  public static func source(_ text: String) -> String {
    text.contains("AC Power") ? "AC Power" : text.contains("Battery Power") ? "Battery" : "Unknown"
  }
  public static func profile() throws -> PowerProfile {
    let settings = try ProcessRunner.text("/usr/bin/pmset", ["-g"])
    let source = try source(ProcessRunner.text("/usr/bin/pmset", ["-g", "ps"]))
    let assertions = try ProcessRunner.text("/usr/bin/pmset", ["-g", "assertions"])
    return PowerProfile(
      source: source, displaySleep: value(settings, key: "displaysleep"),
      diskSleep: value(settings, key: "disksleep"), systemSleep: value(settings, key: "sleep"),
      sleepDisabled: value(settings, key: "SleepDisabled") == 1, preventedBy: preventedBy(settings),
      assertions: assertions.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { $0.hasPrefix("pid ") })
  }
}
