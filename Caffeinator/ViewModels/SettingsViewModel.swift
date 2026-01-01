import Foundation
import SwiftUI
import ServiceManagement

class SettingsViewModel: ObservableObject {
    @AppStorage("defaultDurationId") var defaultDurationId: String = "1h"
    @AppStorage("showTimerInMenuBar") var showTimerInMenuBar: Bool = true
    @AppStorage("notificationsEnabled") var notificationsEnabled: Bool = true
    @AppStorage("globalShortcutEnabled") var globalShortcutEnabled: Bool = true
    
    @Published var defaultModes: Set<CaffeinateMode> = [.idle]
    @Published var timerPresets: [TimerPreset] = []
    
    private let defaultModesKey = "defaultModes"
    private let timerPresetsKey = "timerPresets"
    
    init() {
        loadDefaultModes()
        loadTimerPresets()
    }
    
    var defaultDuration: Duration {
        get {
            Duration.from(id: defaultDurationId) ?? .oneHour
        }
        set {
            defaultDurationId = newValue.id
        }
    }
    
    // MARK: - Timer Presets
    
    private func loadTimerPresets() {
        if let data = UserDefaults.standard.data(forKey: timerPresetsKey),
           let presets = try? JSONDecoder().decode([TimerPreset].self, from: data) {
            timerPresets = presets
        } else {
            timerPresets = TimerPreset.defaults
            saveTimerPresets()
        }
    }
    
    func saveTimerPresets() {
        if let data = try? JSONEncoder().encode(timerPresets) {
            UserDefaults.standard.set(data, forKey: timerPresetsKey)
        }
    }
    
    func addPreset(_ preset: TimerPreset) {
        timerPresets.append(preset)
        saveTimerPresets()
    }
    
    func updatePreset(_ preset: TimerPreset) {
        if let index = timerPresets.firstIndex(where: { $0.id == preset.id }) {
            timerPresets[index] = preset
            saveTimerPresets()
        }
    }
    
    func deletePreset(_ preset: TimerPreset) {
        timerPresets.removeAll { $0.id == preset.id }
        saveTimerPresets()
    }
    
    func resetPresetsToDefaults() {
        timerPresets = TimerPreset.defaults
        saveTimerPresets()
    }
    
    func movePreset(from source: IndexSet, to destination: Int) {
        timerPresets.move(fromOffsets: source, toOffset: destination)
        saveTimerPresets()
    }
    
    // MARK: - Launch at Login
    
    var launchAtLogin: Bool {
        get {
            SMAppService.mainApp.status == .enabled
        }
        set {
            do {
                if newValue {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
                objectWillChange.send()
            } catch {
                print("Failed to update launch at login: \(error)")
            }
        }
    }
    
    // MARK: - Default Modes Persistence
    
    private func loadDefaultModes() {
        if let data = UserDefaults.standard.data(forKey: defaultModesKey),
           let modes = try? JSONDecoder().decode(Set<CaffeinateMode>.self, from: data) {
            defaultModes = modes
        } else {
            defaultModes = [.idle]
        }
    }
    
    func saveDefaultModes() {
        if let data = try? JSONEncoder().encode(defaultModes) {
            UserDefaults.standard.set(data, forKey: defaultModesKey)
        }
    }
    
    func toggleMode(_ mode: CaffeinateMode) {
        if defaultModes.contains(mode) {
            defaultModes.remove(mode)
        } else {
            defaultModes.insert(mode)
        }
        saveDefaultModes()
    }
    
    func isModeEnabled(_ mode: CaffeinateMode) -> Bool {
        defaultModes.contains(mode)
    }
}
