import Foundation

public struct AppError: LocalizedError, Sendable {
  public let message: String
  public init(_ message: String) { self.message = message }
  public var errorDescription: String? { message }
}

public enum Mode: String, Codable, CaseIterable, Identifiable, Sendable {
  case idle = "NoIdleSleep"
  case display = "NoDisplaySleep"
  case server = "ServerMode"
  case network = "NetworkActive"
  case background = "BackgroundTask"
  public var id: String { rawValue }
  public init(from decoder: Decoder) throws {
    let value = try decoder.singleValueContainer().decode(String.self)
    guard let mode = Mode(rawValue: value == "LidClose" ? "ServerMode" : value) else {
      throw AppError("Unknown mode: \(value)")
    }
    self = mode
  }
  public var title: String {
    switch self {
    case .idle: return "Keep awake"
    case .display: return "Keep display on"
    case .server: return "Server Mode"
    case .network: return "Network"
    case .background: return "Background"
    }
  }
  public var symbol: String {
    switch self {
    case .idle: return "moon"
    case .display: return "display"
    case .server: return "server.rack"
    case .network: return "network"
    case .background: return "gearshape"
    }
  }
  public var detail: String {
    switch self {
    case .idle: return "Keep your Mac working. The display can sleep."
    case .display: return "Keep your Mac and its display awake."
    case .server: return "Keep awake with the lid closed. Requires administrator access."
    case .network: return "Keep the system awake while serving network clients."
    case .background: return "Allow background work. The system may enter low power."
    }
  }
  var assertionType: String {
    switch self {
    case .idle, .server: return "PreventUserIdleSystemSleep"
    case .display: return "PreventUserIdleDisplaySleep"
    case .network: return "NetworkClientActive"
    case .background: return "BackgroundTask"
    }
  }
}

public struct Preferences: Equatable, Sendable {
  public var mode: Mode = .idle
  public var duration: Int? = 3600
  public init(mode: Mode = .idle, duration: Int? = 3600) {
    self.mode = mode
    self.duration = duration
  }
}

public struct Status: Codable, Sendable {
  public var isActive = false
  public var mode: Mode?
  public var selectedMode: Mode = .idle
  public var selectedDuration: Int? = 3600
  public var remainingSeconds: Int?
  public var totalSeconds: Int?
  public var busy = false
  public var recoveryRequired = false
  public var error: String?
  public var revision: UInt64 = 0
  enum CodingKeys: String, CodingKey {
    case isActive = "is_active"
    case selectedMode = "selected_mode"
    case selectedDuration = "selected_duration"
    case remainingSeconds = "remaining_seconds"
    case totalSeconds = "total_seconds"
    case recoveryRequired = "recovery_required"
    case mode, busy, error, revision
  }
  public init() {}
  // Raycast expects nullable fields to exist, rather than Codable's omitted nils.
  public func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(isActive, forKey: .isActive)
    try c.encode(mode, forKey: .mode)
    try c.encode(selectedMode, forKey: .selectedMode)
    try c.encode(selectedDuration, forKey: .selectedDuration)
    try c.encode(remainingSeconds, forKey: .remainingSeconds)
    try c.encode(totalSeconds, forKey: .totalSeconds)
    try c.encode(busy, forKey: .busy)
    try c.encode(recoveryRequired, forKey: .recoveryRequired)
    try c.encode(error, forKey: .error)
    try c.encode(revision, forKey: .revision)
  }
}

public struct Telemetry: Sendable {
  public var batteryPercent: Double?
  public var chargingState = "unknown"
  public var systemWatts: Double?
  public var adapterInputWatts: Double?
  public var batteryWatts: Double?
  public var adapterRatingWatts: Double?
  public var batteryVoltage: Double?
  public var batteryCurrentAmps: Double?
  public var timeRemainingMinutes: Int?
  public var updatedAtMS: Int64 = milliseconds()
  public init() {}
}
public struct PowerProfile: Sendable {
  public var source: String
  public var displaySleep: Int?
  public var diskSleep: Int?
  public var systemSleep: Int?
  public var sleepDisabled: Bool
  public var preventedBy: [String]
  public var assertions: [String]
}
public enum HistoryRange: String, CaseIterable, Identifiable, Sendable {
  case hour, day, week
  public var id: String { rawValue }
  public var title: String { ["hour": "1 hour", "day": "24 hours", "week": "7 days"][rawValue]! }
  public var durationMS: Int64 {
    switch self {
    case .hour: return 3_600_000
    case .day: return 86_400_000
    case .week: return 604_800_000
    }
  }
  var bucketMS: Int64 {
    switch self {
    case .hour: return 60_000
    case .day: return 1_800_000
    case .week: return 10_800_000
    }
  }
}
public struct HistoryPoint: Identifiable, Sendable {
  public var sampledAtMS: Int64
  public var systemWatts: Double?
  public var batteryWatts: Double?
  public var batteryPercent: Double?
  public var id: Int64 { sampledAtMS }
  public var date: Date { Date(timeIntervalSince1970: Double(sampledAtMS) / 1000) }
}
public struct SessionRecord: Identifiable, Sendable {
  public var id: Int64
  public var mode: Mode
  public var startedAtMS: Int64
  public var endedAtMS: Int64?
  public var plannedDuration: Int?
  public var endReason: String?
}
public struct PowerHistory: Sendable {
  public var averageSystemWatts: Double?
  public var peakSystemWatts: Double?
  public var sampleCount: Int = 0
  public var sessionSeconds: Int = 0
  public var points: [HistoryPoint] = []
  public var sessions: [SessionRecord] = []
  public init() {}
}
public func milliseconds() -> Int64 { Int64(Date().timeIntervalSince1970 * 1000) }

extension NSLock {
  func locked<T>(_ body: () throws -> T) rethrows -> T {
    lock()
    defer { unlock() }
    return try body()
  }
}
