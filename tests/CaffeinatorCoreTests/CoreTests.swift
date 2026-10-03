import CSQLite
import Foundation
import XCTest

@testable import CaffeinatorCore

final class FakePower: PowerControl {
  var recovery = false, failRestore = false, failRelease = false, failEnable = false
  var releases = 0, restores = 0, creates = 0
  var onCreate: (() throws -> Void)?
  func create(_ mode: Mode) throws -> UInt32 {
    creates += 1
    try onCreate?()
    return UInt32(creates)
  }
  func release(_ id: UInt32) throws {
    if failRelease { throw AppError("Release failed") }
    releases += 1
  }
  func enableServer() throws {
    recovery = true
    if failEnable { throw AppError("Enable failed") }
  }
  func restoreServer() throws {
    restores += 1
    if failRestore { throw AppError("Authorization canceled") }
    recovery = false
  }
  func recoveryNeeded() throws -> Bool { recovery }
}
final class CoreTests: XCTestCase {
  var directory: URL!
  override func setUpWithError() throws {
    directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "caffeinator-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  }
  override func tearDownWithError() throws { try FileManager.default.removeItem(at: directory) }
  func fixture(_ power: FakePower = FakePower(), clock: @escaping () -> TimeInterval = { 10 })
    throws -> (SessionEngine, FakePower)
  {
    (try SessionEngine(storage: Storage(directory: directory), power: power, clock: clock), power)
  }
  func testRestorationFailureRetainsAssertionAndRetry() throws {
    let (engine, power) = try fixture()
    try engine.start(mode: .server, duration: nil)
    power.failRestore = true
    XCTAssertThrowsError(try engine.stop())
    XCTAssertTrue(engine.status().isActive)
    XCTAssertTrue(engine.status().recoveryRequired)
    XCTAssertEqual(power.releases, 0)
    power.failRestore = false
    try engine.stop()
    XCTAssertFalse(engine.status().isActive)
    XCTAssertEqual(power.releases, 1)
  }
  func testReleaseFailureRetainsIDForRetry() throws {
    let (engine, power) = try fixture()
    try engine.start(mode: .idle, duration: nil)
    power.failRelease = true
    XCTAssertThrowsError(try engine.stop())
    XCTAssertTrue(engine.status().isActive)
    power.failRelease = false
    try engine.stop()
    XCTAssertFalse(engine.status().isActive)
  }
  func testStartupRecoveryBlocksActivation() throws {
    let power = FakePower()
    power.recovery = true
    let (engine, _) = try fixture(power)
    XCTAssertTrue(engine.status().recoveryRequired)
    XCTAssertThrowsError(try engine.start(mode: .idle, duration: nil))
    XCTAssertEqual(power.creates, 0)
    try engine.stop()
    try engine.start(mode: .idle, duration: nil)
    try engine.stop()
  }
  func testFailedEnableRetainsGlobalRecovery() throws {
    let power = FakePower()
    power.failEnable = true
    let (engine, _) = try fixture(power)
    XCTAssertThrowsError(try engine.start(mode: .server, duration: nil))
    XCTAssertTrue(engine.status().recoveryRequired)
    XCTAssertEqual(power.releases, 1)
    try engine.stop()
    XCTAssertFalse(engine.status().recoveryRequired)
  }
  func testExpiryDoesNotRepeatAuthorization() throws {
    var now: TimeInterval = 0
    let (engine, power) = try fixture(clock: { now })
    try engine.start(mode: .server, duration: 1)
    power.failRestore = true
    now = 2
    engine.expireIfDue()
    engine.expireIfDue()
    XCTAssertEqual(power.restores, 1)
    XCTAssertTrue(engine.status().isActive)
  }
  func testCountdownRoundsUpAndRecordsExpiry() throws {
    var now: TimeInterval = 0
    let (engine, _) = try fixture(clock: { now })
    try engine.start(mode: .idle, duration: 1)
    now = 0.9
    XCTAssertEqual(engine.status().remainingSeconds, 1)
    engine.expireIfDue()
    XCTAssertTrue(engine.status().isActive)
    now = 1
    engine.expireIfDue()
    XCTAssertFalse(engine.status().isActive)
    XCTAssertEqual(try engine.storage.history(.hour).sessions.first?.endReason, "expired")
  }
  func testInvalidReplacementDoesNotStopSession() throws {
    let (engine, power) = try fixture()
    try engine.start(mode: .idle, duration: nil)
    for duration in [0, -1, 604801] {
      XCTAssertThrowsError(try engine.start(mode: .display, duration: duration))
    }
    XCTAssertTrue(engine.status().isActive)
    XCTAssertEqual(power.releases, 0)
  }
  func testStatusReadableDuringTransitionAndConcurrentCommandRejected() throws {
    let (engine, power) = try fixture()
    power.onCreate = {
      XCTAssertTrue(engine.status().busy)
      XCTAssertThrowsError(try engine.toggle())
    }
    try engine.start(mode: .idle, duration: nil)
    XCTAssertFalse(engine.status().busy)
  }
  func testPreferencesAndLegacyAliasSurviveReopen() throws {
    try Data("{\"selected_mode\":\"LidClose\",\"selected_duration\":7200}".utf8).write(
      to: directory.appendingPathComponent("settings.json"))
    let storage = try Storage(directory: directory)
    XCTAssertEqual(try storage.preferences(), Preferences(mode: .server, duration: 7200))
    try storage.savePreferences(Preferences(mode: .display, duration: nil))
    XCTAssertEqual(
      try Storage(directory: directory).preferences(), Preferences(mode: .display, duration: nil))
  }
  func testExistingV1SchemaUpgradesWithoutLosingPreferences() throws {
    var db: OpaquePointer?
    sqlite3_open(directory.appendingPathComponent("caffeinator.sqlite3").path, &db)
    XCTAssertEqual(
      sqlite3_exec(
        db,
        "CREATE TABLE app_settings(id INTEGER PRIMARY KEY, selected_mode TEXT NOT NULL, selected_duration_seconds INTEGER); INSERT INTO app_settings VALUES(1,'NoDisplaySleep',3600); PRAGMA user_version=1;",
        nil, nil, nil), SQLITE_OK)
    sqlite3_close(db)
    let storage = try Storage(directory: directory)
    XCTAssertEqual(try storage.preferences(), Preferences(mode: .display, duration: 3600))
    XCTAssertEqual(try storage.history(.day).sampleCount, 0)
  }
  func testNewerSchemaIsRejected() throws {
    var db: OpaquePointer?
    sqlite3_open(directory.appendingPathComponent("caffeinator.sqlite3").path, &db)
    sqlite3_exec(db, "PRAGMA user_version=99", nil, nil, nil)
    sqlite3_close(db)
    XCTAssertThrowsError(try Storage(directory: directory))
  }
  func testPowerHistoryAggregationAndSessionOverlap() throws {
    let storage = try Storage(directory: directory)
    let now = milliseconds()
    var sample = Telemetry()
    sample.updatedAtMS = now - 90_000
    sample.systemWatts = 10
    try storage.record(sample)
    sample.updatedAtMS = now - 30_000
    sample.systemWatts = 20
    try storage.record(sample)
    let id = try storage.startSession(mode: .idle, duration: 80, now: now - 100_000)
    try storage.endSession(id: id, reason: "stopped", now: now - 20_000)
    let history = try storage.history(.hour, now: now)
    XCTAssertEqual(history.sampleCount, 2)
    XCTAssertEqual(history.averageSystemWatts, 15)
    XCTAssertEqual(history.peakSystemWatts, 20)
    XCTAssertEqual(history.sessionSeconds, 80)
  }
  func testReconcileClosesInterruptedSessionsExceptRecoveryOwner() throws {
    let storage = try Storage(directory: directory)
    let idle = try storage.startSession(mode: .idle, duration: nil)
    let server = try storage.startSession(mode: .server, duration: nil)
    XCTAssertEqual(try storage.reconcileSessions(serverRecovery: true), server)
    let history = try storage.history(.hour)
    XCTAssertEqual(history.sessions.first(where: { $0.id == idle })?.endReason, "interrupted")
    XCTAssertNil(history.sessions.first(where: { $0.id == server })?.endedAtMS)
  }
  func testMalformedRecoveryFailsClosed() throws {
    try Data("not json".utf8).write(to: directory.appendingPathComponent("power-recovery.json"))
    let power = MacPower(directory: directory)
    XCTAssertThrowsError(try power.recoveryNeeded())
    let engine = try SessionEngine(storage: Storage(directory: directory), power: power)
    XCTAssertTrue(engine.status().recoveryRequired)
    XCTAssertThrowsError(try engine.start(mode: .idle, duration: nil))
    XCTAssertThrowsError(try engine.stop())
    XCTAssertTrue(
      FileManager.default.fileExists(
        atPath: directory.appendingPathComponent("power-recovery.json").path))
  }
  func testServerJournalExistsBeforeGlobalChangeAndRestoresOriginal() throws {
    var override = 0
    let journal = directory.appendingPathComponent("power-recovery.json")
    let power = MacPower(
      directory: directory, readOverride: { override },
      writeOverride: { value in
        let record = try JSONDecoder().decode(RecoveryRecord.self, from: Data(contentsOf: journal))
        XCTAssertEqual(record.sleepDisabled, 0)
        override = value
      })
    try power.enableServer()
    XCTAssertEqual(override, 1)
    XCTAssertTrue(try power.recoveryNeeded())
    try power.restoreServer()
    XCTAssertEqual(override, 0)
    XCTAssertFalse(try power.recoveryNeeded())
  }
  func testCanceledServerChangeClearsJournalOnlyWhenOriginalIsVerified() throws {
    var readable = true
    let power = MacPower(
      directory: directory,
      readOverride: {
        guard readable else { throw AppError("Cannot read override") }
        return 0
      }, writeOverride: { _ in throw AppError("Authorization canceled") })
    XCTAssertThrowsError(try power.enableServer())
    XCTAssertFalse(try power.recoveryNeeded())
    let uncertain = MacPower(
      directory: directory,
      readOverride: {
        guard readable else { throw AppError("Cannot read override") }
        return 0
      },
      writeOverride: { _ in
        readable = false
        throw AppError("Uncertain change")
      })
    XCTAssertThrowsError(try uncertain.enableServer())
    XCTAssertTrue(try uncertain.recoveryNeeded())
    XCTAssertThrowsError(try uncertain.restoreServer())
    XCTAssertTrue(try uncertain.recoveryNeeded())
    readable = true
    try uncertain.restoreServer()
  }
  func testTelemetrySignedCurrentAndUnavailableReadings() {
    let sample = TelemetryReader.parse([
      "InstantAmperage": NSNumber(value: UInt64(bitPattern: -1000)), "Voltage": 12000,
      "CurrentCapacity": 50, "MaxCapacity": 100,
    ])
    XCTAssertEqual(sample.batteryCurrentAmps, -1)
    XCTAssertEqual(sample.batteryWatts, -12)
    XCTAssertEqual(sample.batteryPercent, 50)
    XCTAssertNil(sample.systemWatts)
    XCTAssertNil(sample.adapterInputWatts)
  }
  func testTelemetrySeparatesAdapterRatingAndInput() {
    let sample = TelemetryReader.parse([
      "ExternalConnected": true, "IsCharging": true,
      "PowerTelemetryData": ["SystemLoad": 11383, "BatteryPower": 43168, "SystemPowerIn": 54551],
      "AdapterDetails": ["Watts": 84],
    ])
    XCTAssertEqual(sample.systemWatts, 11.383)
    XCTAssertEqual(sample.adapterInputWatts, 54.551)
    XCTAssertEqual(sample.batteryWatts, 43.168)
    XCTAssertEqual(sample.adapterRatingWatts, 84)
  }
  func testPMSetParsingAndAuthorizationErrors() {
    let text = "SleepDisabled 1\nsleep 5 (sleep prevented by caffeinator, powerd)\ndisplaysleep 15"
    XCTAssertEqual(PowerParser.value(text, key: "sleep"), 5)
    XCTAssertEqual(PowerParser.preventedBy(text), ["caffeinator", "powerd"])
    XCTAssertEqual(PowerParser.source("Now drawing from 'AC Power'"), "AC Power")
    XCTAssertTrue(
      MacPower.authorizationError("User canceled. (-128)").hasPrefix("Authorization canceled"))
    XCTAssertTrue(MacPower.authorizationError("Error (42)").contains("Error (42)"))
  }
  func testProtocolRejectsUnknownAndInvalidFields() throws {
    for json in [
      "{\"command\":\"shell\"}", "{\"command\":\"status\",\"extra\":1}",
      "{\"command\":\"start\",\"mode\":\"NoIdleSleep\",\"duration_secs\":true}",
      "{\"command\":\"start\",\"mode\":\"NoIdleSleep\",\"duration_secs\":1.5}",
      "{\"command\":\"start\",\"mode\":\"NoIdleSleep\",\"duration_secs\":-1}",
    ] {
      XCTAssertThrowsError(try ControlRequest.decode(Data(json.utf8)))
    }
    XCTAssertNil(
      try ControlRequest.decode(
        Data("{\"command\":\"start\",\"mode\":\"NoIdleSleep\",\"duration_secs\":null}".utf8)
      ).duration)
    let object =
      try JSONSerialization.jsonObject(with: JSONEncoder().encode(Status())) as! [String: Any]
    XCTAssertTrue(object["remaining_seconds"] is NSNull)
    XCTAssertTrue(object["error"] is NSNull)
  }
  func testInstanceLockPreventsDuplicateAndSocketPathCollision() throws {
    let lease = try InstanceLease(directory: directory)
    XCTAssertThrowsError(try InstanceLease(directory: directory))
    let (engine, _) = try fixture()
    try Data("preserve me".utf8).write(to: directory.appendingPathComponent("control.sock"))
    let server = ControlServer(engine: engine, lease: lease, show: {})
    XCTAssertThrowsError(try server.start())
    XCTAssertEqual(
      try String(contentsOf: directory.appendingPathComponent("control.sock")), "preserve me")
  }
}
