import AppKit
import CaffeinatorCore
import ServiceManagement
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
  let engine: SessionEngine
  @Published var status: Status
  @Published var telemetry: Telemetry?
  @Published var profile: PowerProfile?
  @Published var history = PowerHistory()
  @Published var historyRange: HistoryRange = .day
  @Published var telemetryError: String?
  @Published var historyError: String?
  @Published var actionError: String?
  @Published var loginEnabled = false
  @Published var working = false
  private var timer: Timer?
  private var refreshRunning = false
  private var tickCount = 0
  var onStatus: ((Status) -> Void)?
  var onQuit: (() -> Void)?
  init(engine: SessionEngine) {
    self.engine = engine
    status = engine.status()
    loginEnabled =
      SMAppService.mainApp.status == .enabled
      || FileManager.default.fileExists(atPath: Self.legacyLogin.path)
    timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
      Task { @MainActor in self?.tick() }
    }
    refresh()
  }
  private func tick() {
    status = engine.status()
    onStatus?(status)
    if status.remainingSeconds == 0 && !status.busy && status.error == nil {
      let engine = engine
      DispatchQueue.global().async { engine.expireIfDue() }
    }
    tickCount += 1
    if tickCount % 2 == 0 { refresh() }
  }
  func perform(_ action: @escaping (SessionEngine) throws -> Void, completion: (() -> Void)? = nil)
  {
    guard !working else { return }
    working = true
    actionError = nil
    let engine = engine
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      var failure: String?
      do { try action(engine) } catch { failure = error.localizedDescription }
      let snapshot = engine.status()
      DispatchQueue.main.async { [weak self] in
        guard let self else { return }
        self.working = false
        self.status = snapshot
        self.actionError = failure
        self.onStatus?(snapshot)
        if failure == nil { completion?() }
        self.refresh()
      }
    }
  }
  func select(mode: Mode? = nil, duration: Int?? = nil) {
    let chosenMode = mode ?? status.selectedMode
    let chosenDuration = duration ?? status.selectedDuration
    perform { try $0.preferences(mode: chosenMode, duration: chosenDuration) }
  }
  func toggle() { perform { try $0.toggle() } }
  func stop() { perform { try $0.stop() } }
  func quit() { perform({ try $0.stop() }, completion: { [weak self] in self?.onQuit?() }) }
  func refresh() {
    guard !refreshRunning else { return }
    refreshRunning = true
    let storage = engine.storage
    let range = historyRange
    let includeProfile = profile == nil || tickCount % 10 == 0
    DispatchQueue.global(qos: .utility).async { [weak self] in
      let sample = Result { try TelemetryReader.read() }
      if case .success(let value) = sample { try? storage.record(value) }
      let history = Result { try storage.history(range) }
      let profile = includeProfile ? try? PowerParser.profile() : nil
      DispatchQueue.main.async { [weak self] in
        guard let self else { return }
        self.refreshRunning = false
        switch sample {
        case .success(let value):
          self.telemetry = value
          self.telemetryError = nil
        case .failure(let error):
          self.telemetry = nil
          self.telemetryError = error.localizedDescription
        }
        if range == self.historyRange {
          switch history {
          case .success(let value):
            self.history = value
            self.historyError = nil
          case .failure(let error): self.historyError = error.localizedDescription
          }
        } else {
          self.refresh()
        }
        if let profile { self.profile = profile }
      }
    }
  }
  var isPreview: Bool {
    engine.storage.directory.standardizedFileURL != Storage.defaultDirectory.standardizedFileURL
  }
  private static var legacyLogin: URL {
    FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
      "Library/LaunchAgents/com.tasnimzotder.caffeinator.plist")
  }
  func setLogin(_ enabled: Bool) {
    guard !isPreview else {
      actionError = "Launch at login is unavailable in an isolated preview."
      return
    }
    do {
      if enabled {
        try SMAppService.mainApp.register()
      } else if SMAppService.mainApp.status != .notRegistered {
        try SMAppService.mainApp.unregister()
      }
      if FileManager.default.fileExists(atPath: Self.legacyLogin.path) {
        _ = try? ProcessRunner.run(
          "/bin/launchctl", ["bootout", "gui/\(getuid())", Self.legacyLogin.path])
        try FileManager.default.removeItem(at: Self.legacyLogin)
      }
      loginEnabled = SMAppService.mainApp.status == .enabled
      if enabled && SMAppService.mainApp.status == .requiresApproval {
        actionError = "Allow Caffeinator in System Settings → Login Items."
        SMAppService.openSystemSettingsLoginItems()
      } else {
        actionError = nil
      }
    } catch { actionError = error.localizedDescription }
  }
}
