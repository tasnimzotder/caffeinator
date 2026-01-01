import Foundation
import AppKit
import Combine

@MainActor
class ProcessWatcher: ObservableObject {
    @Published var runningWatchedProcesses: [NSRunningApplication] = []
    @Published var watchedProcess: NSRunningApplication?
    @Published var watchList: [WatchedProcess] = []
    
    private var cancellables = Set<AnyCancellable>()
    private var observationToken: NSKeyValueObservation?
    
    private let customWatchListKey = "customWatchList"
    
    init() {
        loadWatchList()
        startMonitoring()
    }
    
    // MARK: - Monitoring
    
    func startMonitoring() {
        updateRunningProcesses()
        
        // Listen for app launches
        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.didLaunchApplicationNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateRunningProcesses()
            }
            .store(in: &cancellables)
        
        // Listen for app terminations
        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.didTerminateApplicationNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                self?.handleAppTermination(notification)
            }
            .store(in: &cancellables)
    }
    
    func updateRunningProcesses() {
        let running = NSWorkspace.shared.runningApplications
        let bundleIds = Set(watchList.compactMap { $0.bundleIdentifier?.lowercased() })
        let names = Set(watchList.map { $0.name.lowercased() })
        
        runningWatchedProcesses = running.filter { app in
            if let bundleId = app.bundleIdentifier?.lowercased(), bundleIds.contains(bundleId) {
                return true
            }
            if let name = app.localizedName?.lowercased(), names.contains(name) {
                return true
            }
            return false
        }.sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }
    
    // MARK: - Process Watching
    
    func watchProcess(_ app: NSRunningApplication) {
        stopWatching()
        watchedProcess = app
        
        // Observe termination
        observationToken = app.observe(\.isTerminated, options: [.new]) { [weak self] app, change in
            if app.isTerminated {
                Task { @MainActor in
                    self?.handleWatchedProcessTerminated(app)
                }
            }
        }
    }
    
    func stopWatching() {
        observationToken?.invalidate()
        observationToken = nil
        watchedProcess = nil
    }
    
    private func handleWatchedProcessTerminated(_ app: NSRunningApplication) {
        let processName = app.localizedName ?? "Unknown"
        stopWatching()
        NotificationCenter.default.post(
            name: .watchedProcessTerminated,
            object: nil,
            userInfo: ["processName": processName]
        )
    }
    
    private func handleAppTermination(_ notification: Notification) {
        updateRunningProcesses()
        
        if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
           app.processIdentifier == watchedProcess?.processIdentifier {
            handleWatchedProcessTerminated(app)
        }
    }
    
    // MARK: - Watch List Management
    
    private func loadWatchList() {
        var list = WatchedProcess.defaultWatchList
        
        // Load custom processes
        if let data = UserDefaults.standard.data(forKey: customWatchListKey),
           let custom = try? JSONDecoder().decode([WatchedProcess].self, from: data) {
            list.append(contentsOf: custom)
        }
        
        watchList = list
    }
    
    func addToWatchList(name: String, bundleIdentifier: String?) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        
        // Check for duplicates
        let exists = watchList.contains { process in
            process.name.lowercased() == trimmedName.lowercased() ||
            (bundleIdentifier != nil && process.bundleIdentifier?.lowercased() == bundleIdentifier?.lowercased())
        }
        guard !exists else { return }
        
        let process = WatchedProcess(
            name: trimmedName,
            bundleIdentifier: bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines),
            isBuiltIn: false
        )
        watchList.append(process)
        saveCustomWatchList()
        updateRunningProcesses()
    }
    
    func removeFromWatchList(_ process: WatchedProcess) {
        guard !process.isBuiltIn else { return }
        watchList.removeAll { $0.id == process.id }
        saveCustomWatchList()
        updateRunningProcesses()
    }
    
    private func saveCustomWatchList() {
        let custom = watchList.filter { !$0.isBuiltIn }
        if let data = try? JSONEncoder().encode(custom) {
            UserDefaults.standard.set(data, forKey: customWatchListKey)
        }
    }
    
    // MARK: - Helpers
    
    var builtInProcesses: [WatchedProcess] {
        watchList.filter { $0.isBuiltIn }
    }
    
    var customProcesses: [WatchedProcess] {
        watchList.filter { !$0.isBuiltIn }
    }
}
