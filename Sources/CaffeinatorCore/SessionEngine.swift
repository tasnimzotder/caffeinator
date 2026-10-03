import Foundation

public final class SessionEngine: @unchecked Sendable {
  public let storage: Storage
  private let power: PowerControl
  private let clock: () -> TimeInterval
  private let lock = NSLock(), operation = NSLock()
  private var current = Status()
  private var assertionID: UInt32?
  private var serverOwned = false
  private var started: TimeInterval?
  private var historyID: Int64?

  public init(
    storage: Storage, power: PowerControl,
    clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
  ) throws {
    self.storage = storage
    self.power = power
    self.clock = clock
    let preferences = try storage.preferences()
    current.selectedMode = preferences.mode
    current.selectedDuration = preferences.duration
    do {
      serverOwned = try power.recoveryNeeded()
      if serverOwned { current.error = "An interrupted Server Mode session needs restoration." }
    } catch {
      serverOwned = true
      current.error = error.localizedDescription
    }
    if serverOwned { current.mode = .server }
    historyID = try storage.reconcileSessions(serverRecovery: serverOwned)
  }
  public func status() -> Status {
    lock.locked {
      var result = current
      result.isActive = assertionID != nil || serverOwned
      result.recoveryRequired = serverOwned && (result.error != nil || assertionID == nil)
      if let started, let duration = current.totalSeconds {
        result.remainingSeconds = Int(ceil(max(0, Double(duration) - (clock() - started))))
      }
      return result
    }
  }
  private func transition(_ action: () throws -> Void) throws {
    guard operation.try() else { throw AppError("Another operation is in progress. Please wait.") }
    defer { operation.unlock() }
    lock.locked {
      current.busy = true
      current.revision &+= 1
    }
    do {
      try action()
      lock.locked {
        current.busy = false
        current.error = nil
        current.revision &+= 1
      }
    } catch {
      lock.locked {
        current.busy = false
        current.error = error.localizedDescription
        current.revision &+= 1
      }
      throw error
    }
  }
  public static func validateDuration(_ duration: Int?) throws {
    if let duration, duration < 1 || duration > 604800 {
      throw AppError("Choose a duration between 1 second and 7 days.")
    }
  }
  public func preferences(mode: Mode, duration: Int?) throws {
    try Self.validateDuration(duration)
    try transition {
      guard !status().isActive else {
        throw AppError("Stop your session before changing its defaults.")
      }
      try storage.savePreferences(Preferences(mode: mode, duration: duration))
      lock.locked {
        current.selectedMode = mode
        current.selectedDuration = duration
      }
    }
  }
  public func start(mode: Mode, duration: Int?) throws {
    try Self.validateDuration(duration)
    try transition { try activate(mode: mode, duration: duration) }
  }
  public func toggle() throws {
    try transition {
      let status = status()
      if status.isActive {
        try cleanup(reason: "stopped")
      } else {
        try activate(mode: status.selectedMode, duration: status.selectedDuration)
      }
    }
  }
  private func activate(mode: Mode, duration: Int?) throws {
    guard !status().recoveryRequired else {
      throw AppError("Restore the previous sleep settings before starting a session.")
    }
    try storage.savePreferences(Preferences(mode: mode, duration: duration))
    lock.locked {
      current.selectedMode = mode
      current.selectedDuration = duration
    }
    try cleanup(reason: "replaced")
    let id = try power.create(mode)
    lock.locked {
      assertionID = id
      current.mode = mode
    }
    if mode == .server {
      do {
        try power.enableServer()
        let owned = try power.recoveryNeeded()
        lock.locked { serverOwned = owned }
      } catch {
        let owned = (try? power.recoveryNeeded()) ?? true
        lock.locked { serverOwned = owned }
        do { try power.release(id) } catch {
          throw AppError(
            "Server Mode could not start, and the assertion could not be released: \(error.localizedDescription)"
          )
        }
        lock.locked {
          assertionID = nil
          if !serverOwned { current.mode = nil }
        }
        throw error
      }
    }
    lock.locked {
      started = clock()
      current.totalSeconds = duration
    }
    do {
      let sessionID = try storage.startSession(mode: mode, duration: duration)
      lock.locked { historyID = sessionID }
    } catch {
      try cleanup(reason: "stopped")
      throw error
    }
  }
  private func cleanup(reason: String) throws {
    let (id, owned, sessionID) = lock.locked { (assertionID, serverOwned, historyID) }
    // Restore global power settings before releasing the assertion. A failed
    // authorization preserves ownership and IDs for explicit retry.
    if owned {
      try power.restoreServer()
      lock.locked { serverOwned = false }
    }
    if let id { try power.release(id) }
    lock.locked {
      assertionID = nil
      current.mode = nil
      started = nil
      current.totalSeconds = nil
    }
    if let sessionID { try storage.endSession(id: sessionID, reason: reason) }
    lock.locked { historyID = nil }
  }
  public func stop() throws { try transition { try cleanup(reason: "stopped") } }
  public func expireIfDue() {
    let snapshot = status()
    guard !snapshot.busy, snapshot.error == nil, snapshot.remainingSeconds == 0 else { return }
    try? transition {
      if status().remainingSeconds == 0 { try cleanup(reason: "expired") }
    }
  }
}
