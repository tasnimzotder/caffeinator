import SwiftUI
import AppKit

struct ProcessPickerView: View {
    @EnvironmentObject var processWatcher: ProcessWatcher
    var onWatch: (NSRunningApplication) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if processWatcher.runningWatchedProcesses.isEmpty {
                HStack {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.secondary)
                    Text("No watched apps running")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            } else {
                ForEach(processWatcher.runningWatchedProcesses, id: \.processIdentifier) { app in
                    ProcessRow(app: app, isWatched: processWatcher.watchedProcess?.processIdentifier == app.processIdentifier) {
                        onWatch(app)
                    }
                }
            }
            
            Button {
                SettingsHelper.openSettings()
            } label: {
                HStack {
                    Image(systemName: "plus.circle")
                    Text("Manage watch list...")
                }
                .font(.caption)
            }
            .buttonStyle(.borderless)
            .padding(.top, 4)
        }
    }
}

struct ProcessRow: View {
    let app: NSRunningApplication
    let isWatched: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                if let icon = app.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 16, height: 16)
                } else {
                    Image(systemName: "app")
                        .frame(width: 16, height: 16)
                }
                
                Text(app.localizedName ?? "Unknown")
                    .font(.subheadline)
                
                Spacer()
                
                if isWatched {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 2)
    }
}

// MARK: - Watch List Editor (for Settings)

struct WatchListEditor: View {
    @EnvironmentObject var processWatcher: ProcessWatcher
    @State private var newName = ""
    @State private var newBundleId = ""
    @State private var showingAddSheet = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Built-in Processes
            Section {
                Text("Built-in")
                    .font(.headline)
                
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(processWatcher.builtInProcesses) { process in
                            WatchListRow(process: process, isBuiltIn: true)
                        }
                    }
                }
                .frame(maxHeight: 150)
            }
            
            Divider()
            
            // Custom Processes
            Section {
                HStack {
                    Text("Custom")
                        .font(.headline)
                    
                    Spacer()
                    
                    Button {
                        showingAddSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.borderless)
                }
                
                if processWatcher.customProcesses.isEmpty {
                    Text("No custom processes")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 4) {
                            ForEach(processWatcher.customProcesses) { process in
                                WatchListRow(process: process, isBuiltIn: false) {
                                    processWatcher.removeFromWatchList(process)
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 100)
                }
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            AddProcessSheet(onAdd: { name, bundleId in
                processWatcher.addToWatchList(name: name, bundleIdentifier: bundleId)
                showingAddSheet = false
            })
        }
    }
}

struct WatchListRow: View {
    let process: WatchedProcess
    let isBuiltIn: Bool
    var onDelete: (() -> Void)?
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(process.name)
                    .font(.subheadline)
                if let bundleId = process.bundleIdentifier {
                    Text(bundleId)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            
            Spacer()
            
            if !isBuiltIn, let onDelete = onDelete {
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 2)
    }
}

struct AddProcessSheet: View {
    @Environment(\.dismiss) var dismiss
    @State private var name = ""
    @State private var bundleId = ""
    
    var onAdd: (String, String?) -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            Text("Add Process")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 8) {
                TextField("Process Name", text: $name)
                    .textFieldStyle(.roundedBorder)
                
                TextField("Bundle ID (optional)", text: $bundleId)
                    .textFieldStyle(.roundedBorder)
                
                Text("Tip: You can find the bundle ID in Activity Monitor or using 'osascript -e 'id of app \"AppName\"''")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.bordered)
                
                Button("Add") {
                    onAdd(name, bundleId.isEmpty ? nil : bundleId)
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 300)
    }
}
