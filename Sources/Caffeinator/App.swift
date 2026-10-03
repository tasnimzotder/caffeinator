import AppKit
import CaffeinatorCore
import SwiftUI

@main
struct CaffeinatorApplication {
  @MainActor static func main() {
    if CommandLine.arguments.contains("--headless") {
      Headless.run()
      return
    }
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    withExtendedLifetime(delegate) { app.run() }
  }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
  private var item: NSStatusItem?
  private var popover = NSPopover()
  private var model: AppModel?
  private var server: ControlServer?
  private var observer: NSObjectProtocol?
  private var quitAllowed = false
  static let showNotification = Notification.Name("com.tasnimzotder.caffeinator.show")
  func applicationDidFinishLaunching(_ notification: Notification) {
    do {
      let directory = configuredDirectory()
      let lease = try InstanceLease(directory: directory)
      // Check the existing Tauri process before touching real history.
      let path = directory.appendingPathComponent("control.sock").path
      if controlServiceAlive(path) {
        throw AppError("Another Caffeinator control service is running.")
      }
      let storage = try Storage(directory: directory)
      let engine = try SessionEngine(storage: storage, power: MacPower(directory: directory))
      let model = AppModel(engine: engine)
      self.model = model
      server = ControlServer(engine: engine, lease: lease) { [weak self] in
        DispatchQueue.main.async { self?.show() }
      }
      try server?.start()
      model.onStatus = { [weak self] in self?.updateTray($0) }
      model.onQuit = { [weak self] in
        guard let self else { return }
        self.quitAllowed = true
        self.server?.stop()
        NSApp.terminate(nil)
      }
      item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
      item?.button?.target = self
      item?.button?.action = #selector(togglePopover)
      item?.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
      popover.contentViewController = NSHostingController(
        rootView: ContentView(
          model: model, hide: { [weak self] in self?.popover.performClose(nil) }))
      popover.contentSize = NSSize(width: 400, height: 500)
      popover.behavior = .transient
      popover.delegate = self
      updateTray(model.status)
      observer = DistributedNotificationCenter.default().addObserver(
        forName: Self.showNotification, object: directory.path, queue: .main
      ) { [weak self] _ in
        Task { @MainActor in self?.show() }
      }
      if engine.status().recoveryRequired || CommandLine.arguments.contains("--show") { show() }
    } catch {
      if error.localizedDescription.contains("Another Caffeinator") {
        DistributedNotificationCenter.default().postNotificationName(
          Self.showNotification, object: configuredDirectory().path, userInfo: nil,
          deliverImmediately: true)
      } else {
        let alert = NSAlert()
        alert.messageText = "Caffeinator could not start"
        alert.informativeText = error.localizedDescription
        alert.runModal()
      }
      quitAllowed = true
      NSApp.terminate(nil)
    }
  }
  @objc private func togglePopover() {
    if NSApp.currentEvent?.type == .rightMouseUp {
      let menu = NSMenu()
      menu.addItem(
        withTitle: model?.status.isActive == true ? "Stop session" : "Start session",
        action: #selector(toggleSession), keyEquivalent: ""
      ).target = self
      menu.addItem(withTitle: "Open Caffeinator", action: #selector(openPopover), keyEquivalent: "")
        .target = self
      menu.addItem(.separator())
      menu.addItem(withTitle: "Quit", action: #selector(quitApp), keyEquivalent: "q").target = self
      item?.menu = menu
      item?.button?.performClick(nil)
      item?.menu = nil
    } else {
      popover.isShown ? popover.performClose(nil) : show()
    }
  }
  @objc private func toggleSession() { model?.toggle() }
  @objc private func openPopover() { show() }
  @objc private func quitApp() {
    show()
    model?.quit()
  }
  private func show() {
    guard let button = item?.button else { return }
    NSApp.activate(ignoringOtherApps: true)
    if !popover.isShown {
      popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }
    popover.contentViewController?.view.window?.makeKey()
  }
  private func updateTray(_ status: Status) {
    guard let button = item?.button else { return }
    button.image = NSImage(
      systemSymbolName: status.isActive ? "cup.and.saucer.fill" : "cup.and.saucer",
      accessibilityDescription: "Caffeinator")
    button.image?.isTemplate = true
    button.title =
      status.recoveryRequired
      ? " !" : status.isActive ? " " + trayTime(status.remainingSeconds) : ""
    button.toolTip =
      status.recoveryRequired
      ? "Caffeinator: restore sleep settings"
      : status.isActive ? "Caffeinator: session active" : "Caffeinator"
  }
  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    if quitAllowed { return .terminateNow }
    show()
    model?.quit()
    return .terminateCancel
  }
  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool
  {
    show()
    return true
  }
  func applicationWillTerminate(_ notification: Notification) {
    server?.stop()
    if let observer { DistributedNotificationCenter.default().removeObserver(observer) }
  }
  private func trayTime(_ seconds: Int?) -> String {
    guard let seconds else { return "∞" }
    return seconds >= 3600
      ? String(format: "%d:%02d", seconds / 3600, seconds % 3600 / 60) : "\(seconds / 60)m"
  }
}

func configuredDirectory() -> URL {
  if let path = ProcessInfo.processInfo.environment["CAFFEINATOR_CONFIG_DIR"] {
    return URL(fileURLWithPath: path)
  }
  return Storage.defaultDirectory
}

// Launch the same core without a GUI for isolated integration testing.
enum Headless {
  static var sources: [DispatchSourceSignal] = []
  static func run() {
    do {
      let directory = configuredDirectory()
      let lease = try InstanceLease(directory: directory)
      guard !controlServiceAlive(directory.appendingPathComponent("control.sock").path) else {
        throw AppError("Another Caffeinator control service is running.")
      }
      let storage = try Storage(directory: directory)
      let engine = try SessionEngine(storage: storage, power: MacPower(directory: directory))
      let server = ControlServer(engine: engine, lease: lease, show: {})
      try server.start()
      let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global())
      timer.schedule(deadline: .now() + 1, repeating: 1)
      timer.setEventHandler { engine.expireIfDue() }
      timer.resume()
      for sig in [SIGTERM, SIGINT] {
        signal(sig, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: sig, queue: .global())
        source.setEventHandler {
          do {
            try engine.stop()
            server.stop()
            exit(0)
          } catch { fputs("Cannot quit safely: \(error.localizedDescription)\n", stderr) }
        }
        source.resume()
        sources.append(source)
      }
      print("Caffeinator control service ready")
      withExtendedLifetime((server, timer)) { dispatchMain() }
    } catch {
      fputs("\(error.localizedDescription)\n", stderr)
      exit(1)
    }
  }
}

func controlServiceAlive(_ path: String) -> Bool {
  let fd = socket(AF_UNIX, SOCK_STREAM, 0)
  guard fd >= 0 else { return false }
  defer { close(fd) }
  var address = sockaddr_un()
  address.sun_family = sa_family_t(AF_UNIX)
  let bytes = Array(path.utf8) + [0]
  guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else { return false }
  withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: bytes) }
  return withUnsafePointer(to: &address) {
    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
      connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) == 0
    }
  }
}
