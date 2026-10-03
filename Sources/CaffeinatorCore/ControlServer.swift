import Darwin
import Foundation

public struct ControlRequest {
  public var command: String
  public var mode: Mode?
  public var duration: Int?
  public static func decode(_ data: Data) throws -> ControlRequest {
    guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
      let command = object["command"] as? String
    else { throw AppError("Expected a JSON command") }
    let changes = command == "start" || command == "preferences"
    guard ["status", "preferences", "start", "stop", "toggle", "show"].contains(command),
      Set(object.keys).isSubset(of: changes ? ["command", "mode", "duration_secs"] : ["command"])
    else { throw AppError("Unknown command or fields") }
    var mode: Mode?
    var duration: Int?
    if changes {
      guard let key = object["mode"] as? String,
        let decoded = Mode(rawValue: key == "LidClose" ? "ServerMode" : key)
      else { throw AppError("Invalid mode") }
      mode = decoded
      if let raw = object["duration_secs"], !(raw is NSNull) {
        guard let n = raw as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(),
          n.doubleValue.isFinite,
          n.doubleValue >= 1, n.doubleValue <= 604800, n.doubleValue.rounded() == n.doubleValue
        else { throw AppError("Choose a duration between 1 second and 7 days.") }
        duration = n.intValue
      }
    }
    return ControlRequest(command: command, mode: mode, duration: duration)
  }
}

public final class ControlServer: @unchecked Sendable {
  private let engine: SessionEngine
  private let path: String
  private let show: () -> Void
  private var listener: Int32 = -1
  private var lease: InstanceLease?
  private let clients = DispatchSemaphore(value: 8)
  private let lifecycle = NSLock()
  private var stopped = false
  public init(engine: SessionEngine, lease: InstanceLease? = nil, show: @escaping () -> Void) {
    self.lease = lease
    self.engine = engine
    self.path = engine.storage.directory.appendingPathComponent("control.sock").path
    self.show = show
  }
  public func start() throws {
    if lease == nil { lease = try InstanceLease(directory: engine.storage.directory) }
    var info = stat()
    if lstat(path, &info) == 0 {
      guard (info.st_mode & S_IFMT) == S_IFSOCK else {
        throw AppError("The control socket path is occupied by a non-socket file.")
      }
      // Older Tauri builds do not take instance.lock. Never unlink a live service.
      let probe = socket(AF_UNIX, SOCK_STREAM, 0)
      if probe >= 0 {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8) + [0]
        guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else {
          Darwin.close(probe)
          throw AppError("Control socket path is too long")
        }
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: bytes) }
        let result = withUnsafePointer(to: &address) {
          $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            connect(probe, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
          }
        }
        Darwin.close(probe)
        guard result != 0 else { throw AppError("Another Caffeinator control service is running.") }
      }
      guard unlink(path) == 0 else { throw AppError("Cannot remove stale control socket") }
    } else if errno != ENOENT {
      throw AppError("Cannot inspect control socket")
    }
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else { throw AppError("Cannot create control socket") }
    do {
      var address = sockaddr_un()
      address.sun_family = sa_family_t(AF_UNIX)
      let bytes = Array(path.utf8) + [0]
      guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else {
        throw AppError("Control socket path is too long")
      }
      withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: bytes) }
      address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
      let result = withUnsafePointer(to: &address) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
          Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
        }
      }
      guard result == 0, chmod(path, S_IRUSR | S_IWUSR) == 0, listen(fd, 8) == 0 else {
        throw AppError("Cannot bind private control socket")
      }
      listener = fd
      DispatchQueue.global(qos: .userInitiated).async { [self] in
        while !lifecycle.locked({ stopped }) {
          let client = accept(fd, nil, nil)
          if client < 0 {
            if errno == EINTR { continue }
            break
          }
          guard clients.wait(timeout: .now()) == .success else {
            Darwin.close(client)
            continue
          }
          DispatchQueue.global(qos: .userInitiated).async { [self] in
            defer {
              Darwin.close(client)
              clients.signal()
            }
            handle(client)
          }
        }
      }
    } catch {
      Darwin.close(fd)
      throw error
    }
  }
  public func stop() {
    lifecycle.locked {
      guard !stopped else { return }
      stopped = true
      if listener >= 0 {
        shutdown(listener, SHUT_RDWR)
        Darwin.close(listener)
        listener = -1
        unlink(path)
      }
      lease = nil
    }
  }
  deinit { stop() }
  private func handle(_ fd: Int32) {
    var timeout = timeval(tv_sec: 5, tv_usec: 0)
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
    setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
    var noSignal: Int32 = 1
    setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))
    var data = Data()
    var byte: UInt8 = 0
    var error: String?
    do {
      while data.count <= 8192 {
        guard Darwin.read(fd, &byte, 1) == 1 else {
          throw AppError("Invalid request: expected a JSON line")
        }
        data.append(byte)
        if byte == 10 { break }
      }
      guard data.count <= 8192, data.last == 10 else {
        throw AppError("Request exceeds 8192 bytes")
      }
      let request = try ControlRequest.decode(data)
      switch request.command {
      case "start": try engine.start(mode: request.mode!, duration: request.duration)
      case "preferences": try engine.preferences(mode: request.mode!, duration: request.duration)
      case "toggle": try engine.toggle()
      case "stop": try engine.stop()
      case "show": show()
      default: break
      }
    } catch let failure { error = failure.localizedDescription }
    let status = engine.status()
    if error != nil && status.recoveryRequired { show() }
    struct Response: Encodable {
      let ok: Bool
      let status: Status
      let error: String?
      enum CodingKeys: CodingKey { case ok, status, error }
      func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(ok, forKey: .ok)
        try c.encode(status, forKey: .status)
        try c.encode(error, forKey: .error)
      }
    }
    guard
      var response = try? JSONEncoder().encode(
        Response(ok: error == nil, status: status, error: error))
    else { return }
    response.append(10)
    response.withUnsafeBytes { bytes in
      var offset = 0
      while offset < bytes.count {
        let n = Darwin.write(fd, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
        if n < 0 && errno == EINTR { continue }
        if n <= 0 { break }
        offset += n
      }
    }
  }
}

// Claim the instance before opening/reconciling its database.
public final class InstanceLease {
  private var fd: Int32
  public init(directory: URL) throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    fd = Darwin.open(
      directory.appendingPathComponent("instance.lock").path, O_CREAT | O_RDWR | O_NOFOLLOW,
      S_IRUSR | S_IWUSR)
    guard fd >= 0 else { throw AppError("Cannot create instance lock") }
    guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
      Darwin.close(fd)
      fd = -1
      throw AppError("Another Caffeinator instance is running.")
    }
  }
  deinit {
    if fd >= 0 {
      flock(fd, LOCK_UN)
      Darwin.close(fd)
    }
  }
}
