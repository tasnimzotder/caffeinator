import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settings: SettingsViewModel
    @EnvironmentObject var processWatcher: ProcessWatcher
    
    var body: some View {
        TabView {
            GeneralSettingsTab()
                .environmentObject(settings)
                .tabItem {
                    Label("General", systemImage: "gear")
                }
            
            PresetsSettingsTab()
                .environmentObject(settings)
                .tabItem {
                    Label("Presets", systemImage: "timer")
                }
            
            ProcessSettingsTab()
                .environmentObject(processWatcher)
                .environmentObject(settings)
                .tabItem {
                    Label("Processes", systemImage: "cpu")
                }
            
            NotificationSettingsTab()
                .environmentObject(settings)
                .tabItem {
                    Label("Notifications", systemImage: "bell")
                }
            
            AdvancedSettingsTab()
                .environmentObject(settings)
                .tabItem {
                    Label("Advanced", systemImage: "slider.horizontal.3")
                }
            
            CLISettingsTab()
                .tabItem {
                    Label("CLI", systemImage: "terminal")
                }
            
            AboutTab()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 500, height: 400)
    }
}

// MARK: - General Settings

struct GeneralSettingsTab: View {
    @EnvironmentObject var settings: SettingsViewModel
    
    var body: some View {
        Form {
            Section {
                Picker("Default Duration", selection: $settings.defaultDurationId) {
                    ForEach(Duration.presets, id: \.id) { duration in
                        Text(duration.displayName).tag(duration.id)
                    }
                }
                .pickerStyle(.menu)
                
                Toggle("Show timer in menu bar", isOn: $settings.showTimerInMenuBar)
            } header: {
                Text("Defaults")
            }
            
            Section {
                ForEach(CaffeinateMode.allCases) { mode in
                    Toggle(isOn: Binding(
                        get: { settings.isModeEnabled(mode) },
                        set: { _ in settings.toggleMode(mode) }
                    )) {
                        VStack(alignment: .leading) {
                            Text(mode.name)
                            Text(mode.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("Default Modes")
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Presets Settings

struct PresetsSettingsTab: View {
    @EnvironmentObject var settings: SettingsViewModel
    @State private var showingAddSheet = false
    @State private var editingPreset: TimerPreset? = nil
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Timer Presets")
                    .font(.headline)
                Spacer()
                Button {
                    showingAddSheet = true
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                
                Button {
                    settings.resetPresetsToDefaults()
                } label: {
                    Text("Reset")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
            }
            
            Text("These presets appear in the menu bar for quick access.")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            List {
                ForEach(settings.timerPresets) { preset in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(preset.shortName)
                                .font(.headline)
                            Text(preset.displayName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                        
                        Button {
                            editingPreset = preset
                        } label: {
                            Image(systemName: "pencil")
                        }
                        .buttonStyle(.borderless)
                        
                        Button {
                            settings.deletePreset(preset)
                        } label: {
                            Image(systemName: "trash")
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(.vertical, 4)
                }
                .onMove { source, destination in
                    settings.movePreset(from: source, to: destination)
                }
            }
            .listStyle(.bordered)
        }
        .padding()
        .sheet(isPresented: $showingAddSheet) {
            PresetEditorSheet(preset: nil) { newPreset in
                settings.addPreset(newPreset)
                showingAddSheet = false
            }
        }
        .sheet(item: $editingPreset) { preset in
            PresetEditorSheet(preset: preset) { updatedPreset in
                settings.updatePreset(updatedPreset)
                editingPreset = nil
            }
        }
    }
}

// MARK: - Preset Editor Sheet

struct PresetEditorSheet: View {
    @Environment(\.dismiss) var dismiss
    
    let preset: TimerPreset?
    let onSave: (TimerPreset) -> Void
    
    @State private var hours: Int = 0
    @State private var minutes: Int = 30
    
    var body: some View {
        VStack(spacing: 16) {
            Text(preset == nil ? "Add Preset" : "Edit Preset")
                .font(.headline)
            
            HStack(spacing: 20) {
                VStack {
                    Stepper(value: $hours, in: 0...23) {
                        Text("\(hours)")
                            .font(.system(.title2, design: .rounded, weight: .medium))
                            .frame(minWidth: 30)
                    }
                    Text("hours")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                VStack {
                    Stepper(value: $minutes, in: 0...55, step: 5) {
                        Text("\(minutes)")
                            .font(.system(.title2, design: .rounded, weight: .medium))
                            .frame(minWidth: 30)
                    }
                    Text("minutes")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Text(previewText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.bordered)
                
                Button("Save") {
                    let totalMinutes = hours * 60 + minutes
                    let newPreset = TimerPreset(
                        id: preset?.id ?? UUID(),
                        name: previewText,
                        minutes: totalMinutes
                    )
                    onSave(newPreset)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 260)
        .onAppear {
            if let preset = preset {
                hours = preset.minutes / 60
                minutes = preset.minutes % 60
            }
        }
    }
    
    private var previewText: String {
        let totalMinutes = hours * 60 + minutes
        if totalMinutes == 0 {
            return "Indefinite"
        }
        if hours > 0 && minutes > 0 {
            return "\(hours)h \(minutes)m"
        } else if hours > 0 {
            return "\(hours) hour\(hours > 1 ? "s" : "")"
        } else {
            return "\(minutes) minute\(minutes > 1 ? "s" : "")"
        }
    }
}

// MARK: - Process Settings

struct ProcessSettingsTab: View {
    @EnvironmentObject var processWatcher: ProcessWatcher
    
    var body: some View {
        VStack(alignment: .leading) {
            WatchListEditor()
                .environmentObject(processWatcher)
        }
        .padding()
    }
}

// MARK: - Notification Settings

struct NotificationSettingsTab: View {
    @EnvironmentObject var settings: SettingsViewModel
    
    var body: some View {
        Form {
            Section {
                Toggle("Enable notifications", isOn: $settings.notificationsEnabled)
            } header: {
                Text("Notifications")
            }
            
            if settings.notificationsEnabled {
                Section {
                    Label("Caffeinate timer expired", systemImage: "timer")
                    Label("Watched process terminated", systemImage: "xmark.app")
                } header: {
                    Text("You'll be notified when:")
                }
            }
            
            Section {
                Button("Open System Notifications Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
                        NSWorkspace.shared.open(url)
                    }
                }
            } header: {
                Text("System Settings")
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Advanced Settings

struct AdvancedSettingsTab: View {
    @EnvironmentObject var settings: SettingsViewModel
    
    var body: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: Binding(
                    get: { settings.launchAtLogin },
                    set: { settings.launchAtLogin = $0 }
                ))
            } header: {
                Text("Startup")
            }
            
            Section {
                Toggle("Enable global shortcut", isOn: $settings.globalShortcutEnabled)
                
                if settings.globalShortcutEnabled {
                    HStack {
                        Text("Shortcut:")
                        Spacer()
                        Text("⌘⇧C")
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.quaternary)
                            .cornerRadius(4)
                            .font(.system(.body, design: .monospaced))
                    }
                }
            } header: {
                Text("Keyboard Shortcut")
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - CLI Settings

struct CLISettingsTab: View {
    @State private var isInstalled = false
    @State private var installStatus = ""
    @State private var isProcessing = false
    
    var body: some View {
        Form {
            Section {
                HStack {
                    Text("Status:")
                    Spacer()
                    HStack(spacing: 4) {
                        Image(systemName: isInstalled ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(isInstalled ? .green : .red)
                        Text(isInstalled ? "Installed" : "Not Installed")
                    }
                }
                
                if isInstalled {
                    HStack {
                        Text("Location:")
                        Spacer()
                        Text("/usr/local/bin/caffeinator")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("CLI Tool")
            }
            
            Section {
                HStack {
                    Button(isInstalled ? "Reinstall CLI" : "Install CLI") {
                        installCLI()
                    }
                    .disabled(isProcessing)
                    
                    if isInstalled {
                        Button("Uninstall CLI", role: .destructive) {
                            uninstallCLI()
                        }
                        .disabled(isProcessing)
                    }
                }
                
                if !installStatus.isEmpty {
                    Text(installStatus)
                        .font(.caption)
                        .foregroundStyle(installStatus.contains("Error") ? .red : .green)
                }
            } header: {
                Text("Actions")
            }
            
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("caffeinator on 2h")
                    Text("caffeinator on 30m")
                    Text("caffeinator off")
                    Text("caffeinator status")
                    Text("caffeinator watch docker")
                }
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
            } header: {
                Text("Usage Examples")
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            checkInstallation()
        }
    }
    
    private func checkInstallation() {
        isInstalled = FileManager.default.fileExists(atPath: "/usr/local/bin/caffeinator")
    }
    
    private func installCLI() {
        isProcessing = true
        installStatus = ""
        
        guard let cliPath = Bundle.main.path(forAuxiliaryExecutable: "CaffeinatorCLI") else {
            installStatus = "Error: CLI binary not found in app bundle"
            isProcessing = false
            return
        }
        
        let script = """
        do shell script "mkdir -p /usr/local/bin && cp '\(cliPath)' /usr/local/bin/caffeinator && chmod +x /usr/local/bin/caffeinator" with administrator privileges
        """
        
        DispatchQueue.global(qos: .userInitiated).async {
            var error: NSDictionary?
            if let appleScript = NSAppleScript(source: script) {
                appleScript.executeAndReturnError(&error)
                DispatchQueue.main.async {
                    if let error = error {
                        installStatus = "Error: \(error[NSAppleScript.errorMessage] ?? "Unknown error")"
                    } else {
                        installStatus = "CLI installed successfully!"
                        isInstalled = true
                    }
                    isProcessing = false
                }
            } else {
                DispatchQueue.main.async {
                    installStatus = "Error: Failed to create AppleScript"
                    isProcessing = false
                }
            }
        }
    }
    
    private func uninstallCLI() {
        isProcessing = true
        installStatus = ""
        
        let script = """
        do shell script "rm -f /usr/local/bin/caffeinator" with administrator privileges
        """
        
        DispatchQueue.global(qos: .userInitiated).async {
            var error: NSDictionary?
            if let appleScript = NSAppleScript(source: script) {
                appleScript.executeAndReturnError(&error)
                DispatchQueue.main.async {
                    if let error = error {
                        installStatus = "Error: \(error[NSAppleScript.errorMessage] ?? "Unknown error")"
                    } else {
                        installStatus = "CLI uninstalled successfully!"
                        isInstalled = false
                    }
                    isProcessing = false
                }
            } else {
                DispatchQueue.main.async {
                    installStatus = "Error: Failed to create AppleScript"
                    isProcessing = false
                }
            }
        }
    }
}

// MARK: - About Tab

struct AboutTab: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "cup.and.saucer.fill")
                .font(.system(size: 48))
                .foregroundStyle(.brown)
            
            Text("Caffeinator")
                .font(.title)
                .fontWeight(.bold)
            
            Text("Version 0.0.1-alpha")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            Text("A modern, developer-friendly macOS menu bar app for managing system sleep.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Divider()
                .padding(.vertical, 8)
            
            VStack(spacing: 8) {
                Link(destination: URL(string: "https://github.com/tasnimzotder/caffeinator")!) {
                    Label("GitHub Repository", systemImage: "link")
                }
                
                Link(destination: URL(string: "https://github.com/tasnimzotder/caffeinator/issues")!) {
                    Label("Report an Issue", systemImage: "exclamationmark.bubble")
                }
            }
            .font(.caption)
            
            Spacer()
        }
        .padding()
    }
}
