import Foundation
import Combine

@MainActor
class CaffeinateManager: ObservableObject {
    @Published private(set) var isActive = false
    @Published private(set) var remainingSeconds: Int?
    @Published private(set) var activeModes: Set<CaffeinateMode> = []
    @Published private(set) var activeDuration: Duration?
    @Published private(set) var watchedProcessName: String?
    
    private var process: Process?
    private var timer: Timer?
    private var endTime: Date?
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        // Listen for watched process termination
        NotificationCenter.default.publisher(for: .watchedProcessTerminated)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                let processName = notification.userInfo?["processName"] as? String
                self?.handleWatchedProcessTerminated(processName: processName)
            }
            .store(in: &cancellables)
    }
    
    func activate(duration: Duration, modes: Set<CaffeinateMode>) {
        deactivate() // Stop any existing process
        
        guard !modes.isEmpty else { return }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
        
        var arguments = modes.map { $0.rawValue }
        if let seconds = duration.seconds {
            arguments.append("-t")
            arguments.append(String(seconds))
        }
        process.arguments = arguments
        
        // Suppress output
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        
        do {
            try process.run()
            self.process = process
            self.isActive = true
            self.activeModes = modes
            self.activeDuration = duration
            
            if let seconds = duration.seconds {
                self.endTime = Date().addingTimeInterval(TimeInterval(seconds))
                self.remainingSeconds = seconds
                startTimer()
            } else {
                self.remainingSeconds = nil
                self.endTime = nil
            }
            
            // Monitor process termination
            process.terminationHandler = { [weak self] _ in
                Task { @MainActor in
                    self?.handleTermination()
                }
            }
        } catch {
            print("Failed to start caffeinate: \(error)")
        }
    }
    
    func activateForProcess(modes: Set<CaffeinateMode>, processName: String) {
        deactivate()
        
        guard !modes.isEmpty else { return }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
        process.arguments = modes.map { $0.rawValue }
        
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        
        do {
            try process.run()
            self.process = process
            self.isActive = true
            self.activeModes = modes
            self.activeDuration = .indefinite
            self.watchedProcessName = processName
            self.remainingSeconds = nil
            self.endTime = nil
            
            process.terminationHandler = { [weak self] _ in
                Task { @MainActor in
                    self?.handleTermination()
                }
            }
        } catch {
            print("Failed to start caffeinate: \(error)")
        }
    }
    
    func deactivate() {
        timer?.invalidate()
        timer = nil
        
        if let process = process, process.isRunning {
            process.terminate()
        }
        process = nil
        
        isActive = false
        remainingSeconds = nil
        endTime = nil
        activeModes = []
        activeDuration = nil
        watchedProcessName = nil
    }
    
    func toggle(duration: Duration, modes: Set<CaffeinateMode>) {
        if isActive {
            deactivate()
        } else {
            activate(duration: duration, modes: modes)
        }
    }
    
    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateRemainingTime()
            }
        }
    }
    
    private func updateRemainingTime() {
        guard let endTime = endTime else { return }
        let remaining = Int(endTime.timeIntervalSinceNow)
        if remaining <= 0 {
            remainingSeconds = 0
            deactivate()
            NotificationCenter.default.post(name: .caffeinateExpired, object: nil)
        } else {
            remainingSeconds = remaining
        }
    }
    
    private func handleTermination() {
        let wasActive = isActive
        isActive = false
        remainingSeconds = nil
        endTime = nil
        timer?.invalidate()
        timer = nil
        activeModes = []
        activeDuration = nil
        watchedProcessName = nil
        
        if wasActive {
            NotificationCenter.default.post(name: .caffeinateExpired, object: nil)
        }
    }
    
    private func handleWatchedProcessTerminated(processName: String?) {
        if watchedProcessName != nil {
            deactivate()
        }
    }
}

extension Notification.Name {
    static let watchedProcessTerminated = Notification.Name("watchedProcessTerminated")
    static let caffeinateExpired = Notification.Name("caffeinateExpired")
    static let toggleCaffeinateShortcut = Notification.Name("toggleCaffeinateShortcut")
}
