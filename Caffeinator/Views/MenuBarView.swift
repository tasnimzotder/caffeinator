import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var manager: CaffeinateManager
    @EnvironmentObject var processWatcher: ProcessWatcher
    @EnvironmentObject var settings: SettingsViewModel
    
    @State private var selectedModes: Set<CaffeinateMode> = [.idle]
    @State private var showCustomDuration = false
    @State private var customHours: Int = 0
    @State private var customMinutes: Int = 30
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showCustomDuration {
                // Custom Duration Picker View
                customDurationView
            } else {
                // Header
                header
                    .padding(.bottom, Spacing.md)
                
                Divider()
                
                // Main Content
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.lg) {
                        if manager.isActive {
                            activeSessionView
                        } else {
                            quickActionsSection
                            modesSection
                            developerPresetsSection
                            processWatchSection
                        }
                    }
                    .padding(.vertical, Spacing.md)
                }
                
                Divider()
                
                // Footer
                footer
                    .padding(.top, Spacing.md)
            }
        }
        .padding(Spacing.md)
        .frame(width: Layout.menuBarWidth)
        .onAppear {
            selectedModes = settings.defaultModes
        }
    }
    
    // MARK: - Header
    
    private var header: some View {
        HStack(spacing: Spacing.sm) {
            AnimatedCoffeeIcon(isActive: manager.isActive)
                .frame(width: 28, height: 28)
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Spacing.xs) {
                    Text(manager.isActive ? "Active" : "Inactive")
                        .font(.headline)
                    
                    StatusIndicator(isActive: manager.isActive)
                }
                
                if manager.isActive {
                    statusSubtitle
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            if manager.isActive {
                Button("Stop") {
                    withAnimation(AppAnimation.spring) {
                        manager.deactivate()
                        processWatcher.stopWatching()
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(.red)
            }
        }
    }
    
    @ViewBuilder
    private var statusSubtitle: some View {
        if let processName = manager.watchedProcessName {
            Label("Watching \(processName)", systemImage: "eye")
        } else if let remaining = manager.remainingSeconds {
            Text(TimeFormat.format(remaining, style: .remaining))
        } else {
            Text("Running indefinitely")
        }
    }
    
    // MARK: - Active Session View
    
    private var activeSessionView: some View {
        VStack(spacing: Spacing.lg) {
            // Timer Card
            if let remaining = manager.remainingSeconds {
                VStack(spacing: Spacing.sm) {
                    Text(TimeFormat.format(remaining, style: .standard))
                        .font(.system(size: 36, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                    
                    if let duration = manager.activeDuration, let total = duration.seconds {
                        ProgressView(value: Double(remaining), total: Double(total))
                            .tint(.accentColor)
                    }
                }
                .cardStyle()
            } else if manager.watchedProcessName != nil {
                // Indefinite with process watching
                VStack(spacing: Spacing.sm) {
                    Image(systemName: "infinity")
                        .font(.system(size: 36, weight: .medium))
                        .foregroundStyle(.primary)
                    
                    Text("Running indefinitely")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .cardStyle()
            }
            
            // Watched Process
            if let processName = manager.watchedProcessName {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("Watching Process")
                        .sectionHeader()
                    
                    HStack(spacing: Spacing.sm) {
                        Image(systemName: "eye.fill")
                            .foregroundStyle(.blue)
                        
                        Text(processName)
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        Spacer()
                        
                        Text("Will stop when process ends")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(Spacing.sm)
                    .background(Color.blue.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.sm))
                }
            }
            
            // Active Modes
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("Active Modes")
                    .sectionHeader()
                
                HStack(spacing: Spacing.sm) {
                    ForEach(Array(manager.activeModes), id: \.self) { mode in
                        Label(mode.name, systemImage: mode.icon)
                            .pillStyle(isActive: true)
                    }
                }
            }
        }
    }
    
    // MARK: - Quick Actions Section
    
    private var quickActionsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Keep Awake")
                .sectionHeader()
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: Spacing.sm) {
                ForEach(settings.timerPresets) { preset in
                    Button(preset.shortName) {
                        withAnimation(AppAnimation.spring) {
                            manager.activate(duration: preset.duration, modes: selectedModes)
                        }
                    }
                    .buttonStyle(QuickActionButtonStyle(isSelected: false))
                }
                
                Button {
                    withAnimation(AppAnimation.snappy) {
                        showCustomDuration = true
                    }
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .buttonStyle(QuickActionButtonStyle(isSelected: false))
            }
        }
    }
    
    // MARK: - Custom Duration View
    
    private var customDurationView: some View {
        VStack(spacing: Spacing.md) {
            HStack {
                Button {
                    withAnimation(AppAnimation.snappy) {
                        showCustomDuration = false
                    }
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.borderless)
                
                Text("Custom Duration")
                    .font(.headline)
                
                Spacer()
            }
            
            Divider()
            
            Spacer()
            
            HStack(spacing: Spacing.xl) {
                VStack(spacing: Spacing.xs) {
                    Text("\(customHours)")
                        .font(.system(size: 32, weight: .medium, design: .rounded))
                        .monospacedDigit()
                    
                    Stepper("", value: $customHours, in: 0...23)
                        .labelsHidden()
                    
                    Text("hours")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Text(":")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(.secondary)
                
                VStack(spacing: Spacing.xs) {
                    Text("\(customMinutes)")
                        .font(.system(size: 32, weight: .medium, design: .rounded))
                        .monospacedDigit()
                    
                    Stepper("", value: $customMinutes, in: 0...55, step: 5)
                        .labelsHidden()
                    
                    Text("minutes")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Text(customDurationPreview)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            Spacer()
            
            Button {
                let totalSeconds = (customHours * 3600) + (customMinutes * 60)
                let duration: Duration = totalSeconds == 0 ? .indefinite : .custom(seconds: totalSeconds)
                manager.activate(duration: duration, modes: selectedModes)
                withAnimation(AppAnimation.snappy) {
                    showCustomDuration = false
                }
            } label: {
                Text("Start")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(customHours == 0 && customMinutes == 0)
            .controlSize(.large)
        }
        .padding(.vertical, Spacing.sm)
    }
    
    private var customDurationPreview: String {
        let totalMinutes = customHours * 60 + customMinutes
        if totalMinutes == 0 {
            return "Select a duration"
        }
        if customHours > 0 && customMinutes > 0 {
            return "Keep awake for \(customHours)h \(customMinutes)m"
        } else if customHours > 0 {
            return "Keep awake for \(customHours) hour\(customHours > 1 ? "s" : "")"
        } else {
            return "Keep awake for \(customMinutes) minutes"
        }
    }
    
    // MARK: - Modes Section
    
    private var modesSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Modes")
                .sectionHeader()
            
            HStack(spacing: Spacing.sm) {
                ForEach(CaffeinateMode.allCases) { mode in
                    Button {
                        withAnimation(AppAnimation.snappy) {
                            toggleMode(mode)
                        }
                    } label: {
                        Label(mode.shortName, systemImage: mode.icon)
                    }
                    .buttonStyle(ModeButtonStyle(isSelected: selectedModes.contains(mode)))
                    .help(mode.description)
                }
            }
        }
    }
    
    // MARK: - Developer Presets Section
    
    private var developerPresetsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Developer Presets")
                .sectionHeader()
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.sm) {
                    ForEach(DeveloperPreset.all) { preset in
                        Button {
                            withAnimation(AppAnimation.spring) {
                                manager.activate(duration: preset.duration, modes: preset.modes)
                            }
                        } label: {
                            VStack(spacing: Spacing.xs) {
                                Image(systemName: preset.icon)
                                    .font(.title3)
                                Text(preset.name)
                                    .font(.caption2)
                                    .lineLimit(1)
                            }
                            .frame(width: 70, height: 50)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .help(preset.description)
                    }
                }
            }
        }
    }
    
    // MARK: - Process Watch Section
    
    private var processWatchSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Watch Process")
                .sectionHeader()
            
            if processWatcher.runningWatchedProcesses.isEmpty {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.secondary)
                    Text("No watched apps running")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, Spacing.xs)
            } else {
                VStack(spacing: Spacing.xs) {
                    ForEach(processWatcher.runningWatchedProcesses.prefix(3), id: \.processIdentifier) { app in
                        ProcessRow(
                            app: app,
                            isWatched: processWatcher.watchedProcess?.processIdentifier == app.processIdentifier
                        ) {
                            processWatcher.watchProcess(app)
                            manager.activateForProcess(modes: selectedModes, processName: app.localizedName ?? "Unknown")
                        }
                    }
                }
            }
            
            Button {
                SettingsHelper.openSettings()
            } label: {
                Label("Manage watch list", systemImage: "ellipsis.circle")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
        }
    }
    
    // MARK: - Footer
    
    private var footer: some View {
        HStack {
            Button {
                SettingsHelper.openSettings()
            } label: {
                Image(systemName: "gear")
            }
            .buttonStyle(.borderless)
            
            Spacer()
            
            Text("Toggle: ")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            +
            Text("⌘⇧C")
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
            
            Spacer()
            
            Button("Quit") {
                manager.deactivate()
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
        }
    }
    
    // MARK: - Helpers
    
    private func toggleMode(_ mode: CaffeinateMode) {
        if selectedModes.contains(mode) {
            if selectedModes.count > 1 {
                selectedModes.remove(mode)
            }
        } else {
            selectedModes.insert(mode)
        }
    }
}

// MARK: - Mode Extensions

extension CaffeinateMode {
    var icon: String {
        switch self {
        case .display: return "display"
        case .idle: return "moon.zzz"
        case .system: return "bolt.fill"
        case .disk: return "internaldrive"
        }
    }
    
    var shortName: String {
        switch self {
        case .display: return "Display"
        case .idle: return "Idle"
        case .system: return "System"
        case .disk: return "Disk"
        }
    }
}
