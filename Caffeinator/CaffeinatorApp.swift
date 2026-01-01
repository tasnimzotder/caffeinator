import SwiftUI
import Combine

@main
struct CaffeinatorApp: App {
    @StateObject private var caffeinateManager = CaffeinateManager()
    @StateObject private var processWatcher = ProcessWatcher()
    @StateObject private var settings = SettingsViewModel()
    
    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(caffeinateManager)
                .environmentObject(processWatcher)
                .environmentObject(settings)
                .onAppear {
                    setupGlobalShortcut()
                    observeShortcutToggle()
                }
        } label: {
            MenuBarLabel(
                isActive: caffeinateManager.isActive,
                remainingSeconds: caffeinateManager.remainingSeconds,
                showTimer: settings.showTimerInMenuBar
            )
        }
        .menuBarExtraStyle(.window)
        
        Settings {
            SettingsView()
                .environmentObject(settings)
                .environmentObject(processWatcher)
        }
    }
    
    init() {
        setupNotificationObservers()
        requestNotificationPermission()
    }
    
    private func setupNotificationObservers() {
        // Handle caffeinate expiration notifications
        NotificationCenter.default.addObserver(
            forName: .caffeinateExpired,
            object: nil,
            queue: .main
        ) { _ in
            if SettingsViewModel().notificationsEnabled {
                NotificationManager.shared.notifyCaffeinateExpired()
            }
        }
        
        // Handle watched process termination notifications
        NotificationCenter.default.addObserver(
            forName: .watchedProcessTerminated,
            object: nil,
            queue: .main
        ) { notification in
            if SettingsViewModel().notificationsEnabled {
                let processName = notification.userInfo?["processName"] as? String ?? "Process"
                NotificationManager.shared.notifyWatchedProcessEnded(processName: processName)
            }
        }
    }
    
    private func setupGlobalShortcut() {
        guard settings.globalShortcutEnabled else { return }
        
        GlobalShortcutManager.shared.register {
            NotificationCenter.default.post(name: .toggleCaffeinateShortcut, object: nil)
        }
    }
    
    private func observeShortcutToggle() {
        NotificationCenter.default.addObserver(
            forName: .toggleCaffeinateShortcut,
            object: nil,
            queue: .main
        ) { [self] _ in
            Task { @MainActor in
                caffeinateManager.toggle(duration: settings.defaultDuration, modes: settings.defaultModes)
            }
        }
    }
    
    private func requestNotificationPermission() {
        NotificationManager.shared.requestPermission()
    }
}

// MARK: - Menu Bar Label

struct MenuBarLabel: View {
    let isActive: Bool
    let remainingSeconds: Int?
    let showTimer: Bool
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: isActive ? "cup.and.saucer.fill" : "cup.and.saucer")
            
            if isActive, showTimer, let seconds = remainingSeconds {
                Text(formatCompactTime(seconds))
                    .monospacedDigit()
                    .font(.caption)
            }
        }
    }
    
    private func formatCompactTime(_ seconds: Int) -> String {
        TimeFormat.format(seconds, style: .compact)
    }
}
