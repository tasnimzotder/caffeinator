import CSQLite
import Foundation

public final class Storage: @unchecked Sendable {
  public let directory: URL
  private var database: OpaquePointer?
  private let lock = NSLock()
  private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
  public static var defaultDirectory: URL {
    FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/caffeinator")
  }
  public init(directory: URL = Storage.defaultDirectory) throws {
    self.directory = directory
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let path = directory.appendingPathComponent("caffeinator.sqlite3").path
    guard
      sqlite3_open_v2(
        path, &database, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil)
        == SQLITE_OK
    else {
      let message = database.map { String(cString: sqlite3_errmsg($0)) } ?? "Unknown error"
      sqlite3_close(database)
      database = nil
      throw AppError("Cannot open Caffeinator database: \(message)")
    }
    do {
      sqlite3_busy_timeout(database, 5000)
      try execute("PRAGMA journal_mode=WAL; PRAGMA foreign_keys=ON;")
      let version = Int(try rows("PRAGMA user_version")[0][0] as? Int64 ?? 0)
      guard version <= 2 else {
        throw AppError("Database version \(version) is newer than this app supports.")
      }
      if version == 0 { try execute(Schema.v1) }
      if version <= 1 { try execute(Schema.v2) }
      if try rows("SELECT id FROM app_settings WHERE id=1").isEmpty {
        let legacy = directory.appendingPathComponent("settings.json")
        var preferences = Preferences()
        if let data = try? Data(contentsOf: legacy),
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let key = object["selected_mode"] as? String,
          let mode = Mode(rawValue: key == "LidClose" ? "ServerMode" : key)
        {
          preferences.mode = mode
          if object.keys.contains("selected_duration") {
            preferences.duration = (object["selected_duration"] as? NSNumber)?.intValue
            if let n = preferences.duration, n < 1 || n > 604800 { preferences.duration = nil }
          }
        }
        try savePreferences(preferences)
        // Leave the legacy file as a rollback reference; SQLite takes precedence.
      }
    } catch {
      sqlite3_close(database)
      database = nil
      throw error
    }
  }
  deinit { sqlite3_close(database) }
  private func execute(_ sql: String) throws {
    guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else { throw failure() }
  }
  private func failure() -> AppError {
    AppError("Storage: \(String(cString: sqlite3_errmsg(database)))")
  }
  @discardableResult
  private func rows(_ sql: String, _ values: [Any?] = []) throws -> [[Any?]] {
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
      throw failure()
    }
    defer { sqlite3_finalize(statement) }
    for (index, value) in values.enumerated() {
      let i = Int32(index + 1)
      let rc: Int32
      switch value {
      case let n as Int64: rc = sqlite3_bind_int64(statement, i, n)
      case let n as Int: rc = sqlite3_bind_int64(statement, i, Int64(n))
      case let n as Double: rc = sqlite3_bind_double(statement, i, n)
      case let s as String: rc = sqlite3_bind_text(statement, i, s, -1, Self.transient)
      case nil: rc = sqlite3_bind_null(statement, i)
      default: throw AppError("Unsupported database value")
      }
      guard rc == SQLITE_OK else { throw failure() }
    }
    var result: [[Any?]] = []
    while true {
      let rc = sqlite3_step(statement)
      if rc == SQLITE_DONE { break }
      guard rc == SQLITE_ROW else { throw failure() }
      result.append(
        (0..<sqlite3_column_count(statement)).map { i -> Any? in
          switch sqlite3_column_type(statement, i) {
          case SQLITE_INTEGER: return sqlite3_column_int64(statement, i)
          case SQLITE_FLOAT: return sqlite3_column_double(statement, i)
          case SQLITE_TEXT: return String(cString: sqlite3_column_text(statement, i))
          default: return nil
          }
        })
    }
    return result
  }
  public func preferences() throws -> Preferences {
    try lock.locked {
      guard
        let row = try rows(
          "SELECT selected_mode, selected_duration_seconds FROM app_settings WHERE id=1"
        ).first,
        let key = row[0] as? String, let mode = Mode(rawValue: key)
      else { throw AppError("Invalid stored preferences") }
      return Preferences(mode: mode, duration: (row[1] as? Int64).map(Int.init))
    }
  }
  public func savePreferences(_ preferences: Preferences) throws {
    _ = try lock.locked {
      try rows(
        """
        INSERT INTO app_settings VALUES (1, ?1, ?2)
        ON CONFLICT(id) DO UPDATE SET selected_mode=excluded.selected_mode,
            selected_duration_seconds=excluded.selected_duration_seconds
        """, [preferences.mode.rawValue, preferences.duration])
    }
  }
  public func startSession(mode: Mode, duration: Int?, now: Int64 = milliseconds()) throws -> Int64
  {
    return try lock.locked {
      try rows(
        "INSERT INTO session_history (mode, started_at_ms, planned_duration_seconds) VALUES (?1, ?2, ?3)",
        [mode.rawValue, now, duration])
      return sqlite3_last_insert_rowid(database)
    }
  }
  public func endSession(id: Int64, reason: String, now: Int64 = milliseconds()) throws {
    _ = try lock.locked {
      try rows(
        "UPDATE session_history SET ended_at_ms=MAX(started_at_ms, ?1), end_reason=?2 WHERE id=?3 AND ended_at_ms IS NULL",
        [now, reason, id])
    }
  }
  public func reconcileSessions(serverRecovery: Bool) throws -> Int64? {
    try lock.locked {
      let survivor =
        serverRecovery
        ? try rows(
          "SELECT id FROM session_history WHERE ended_at_ms IS NULL AND mode='ServerMode' ORDER BY started_at_ms DESC LIMIT 1"
        ).first?[0] as? Int64 : nil
      try rows(
        "UPDATE session_history SET ended_at_ms=MAX(started_at_ms, ?1), end_reason='interrupted' WHERE ended_at_ms IS NULL AND (?2 IS NULL OR id != ?2)",
        [milliseconds(), survivor])
      return survivor
    }
  }
  public func record(_ sample: Telemetry) throws {
    try lock.locked {
      let bucket = sample.updatedAtMS / 30_000 * 30_000
      try rows(
        """
        INSERT INTO power_samples VALUES (?1, ?2, ?3, ?4, ?5, ?6)
        ON CONFLICT(sampled_at_ms) DO UPDATE SET system_watts=excluded.system_watts,
            adapter_input_watts=excluded.adapter_input_watts, battery_watts=excluded.battery_watts,
            battery_percent=excluded.battery_percent, charging_state=excluded.charging_state
        """,
        [
          bucket, sample.systemWatts, sample.adapterInputWatts, sample.batteryWatts,
          sample.batteryPercent, sample.chargingState,
        ])
      try rows("DELETE FROM power_samples WHERE sampled_at_ms < ?1", [milliseconds() - 604_800_000])
    }
  }
  public func history(_ range: HistoryRange, now: Int64 = milliseconds()) throws -> PowerHistory {
    try lock.locked {
      let from = max(0, now - range.durationMS)
      var history = PowerHistory()
      history.points = try rows(
        """
        SELECT (sampled_at_ms / ?2) * ?2, AVG(system_watts), AVG(battery_watts), AVG(battery_percent)
        FROM power_samples WHERE sampled_at_ms BETWEEN ?1 AND ?3 GROUP BY 1 ORDER BY 1
        """, [from, range.bucketMS, now]
      ).map {
        HistoryPoint(
          sampledAtMS: $0[0] as! Int64, systemWatts: $0[1] as? Double,
          batteryWatts: $0[2] as? Double, batteryPercent: $0[3] as? Double)
      }
      let summary = try rows(
        "SELECT AVG(system_watts), MAX(system_watts), COUNT(*) FROM power_samples WHERE sampled_at_ms BETWEEN ?1 AND ?2",
        [from, now])[0]
      history.averageSystemWatts = summary[0] as? Double
      history.peakSystemWatts = summary[1] as? Double
      history.sampleCount = Int(summary[2] as? Int64 ?? 0)
      let seconds =
        try rows(
          """
          SELECT COALESCE(SUM(MAX(0, MIN(COALESCE(ended_at_ms, ?2), ?2) - MAX(started_at_ms, ?1))) / 1000, 0)
          FROM session_history WHERE started_at_ms <= ?2 AND COALESCE(ended_at_ms, ?2) >= ?1
          """, [from, now])[0][0] as? Int64 ?? 0
      history.sessionSeconds = Int(seconds)
      history.sessions = try rows(
        """
        SELECT id, mode, started_at_ms, ended_at_ms, planned_duration_seconds, end_reason
        FROM session_history WHERE started_at_ms <= ?2 AND COALESCE(ended_at_ms, ?2) >= ?1
        ORDER BY started_at_ms DESC LIMIT 6
        """, [from, now]
      ).map {
        guard let key = $0[1] as? String, let mode = Mode(rawValue: key) else {
          throw AppError("Invalid session mode")
        }
        return SessionRecord(
          id: $0[0] as! Int64, mode: mode, startedAtMS: $0[2] as! Int64,
          endedAtMS: $0[3] as? Int64, plannedDuration: ($0[4] as? Int64).map(Int.init),
          endReason: $0[5] as? String)
      }
      return history
    }
  }
}
