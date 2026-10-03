import CaffeinatorCore
import Charts
import SwiftUI

struct ContentView: View {
  @ObservedObject var model: AppModel
  @State private var tab = "Session"
  var hide: () -> Void = {}
  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 10) {
        Image(systemName: "cup.and.saucer.fill").font(.title2).foregroundStyle(.orange)
        VStack(alignment: .leading, spacing: 2) {
          Text("Caffeinator").font(.headline)
          Text(
            model.status.recoveryRequired
              ? "Restoration needed"
              : model.status.isActive ? "Keeping your Mac awake" : "Ready when you are"
          )
          .font(.caption).foregroundStyle(.secondary)
        }
        Spacer()
        if model.working || model.status.busy { ProgressView().controlSize(.small) }
        Circle().fill(
          model.status.recoveryRequired ? .red : model.status.isActive ? .green : .secondary
        ).frame(width: 8, height: 8)
      }.padding(16)
      Picker("View", selection: $tab) {
        ForEach(["Session", "Power", "History", "Settings"], id: \.self) { Text($0) }
      }.pickerStyle(.segmented).padding(.horizontal, 16).padding(.bottom, 12)
      Divider()
      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          if let error = model.actionError ?? model.status.error {
            Label(error, systemImage: "exclamationmark.triangle.fill")
              .font(.callout).foregroundStyle(.red).padding(12)
              .frame(maxWidth: .infinity, alignment: .leading)
              .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
          }
          switch tab {
          case "Power": PowerView(model: model)
          case "History": HistoryView(model: model)
          case "Settings": SettingsView(model: model)
          default: SessionView(model: model)
          }
        }.padding(16)
      }
      Divider()
      HStack {
        Text("Native for macOS").font(.caption).foregroundStyle(.secondary)
        Spacer()
        Button("Quit") { model.quit() }.buttonStyle(.plain).font(.caption)
          .disabled(model.working || model.status.busy)
      }.padding(.horizontal, 16).padding(.vertical, 8)
    }.frame(width: 400, height: 500)
      .background(Button("Hide", action: hide).keyboardShortcut(.cancelAction).hidden())
  }
}

struct SessionView: View {
  @ObservedObject var model: AppModel
  @State private var customMinutes = "90"
  private var disabled: Bool { model.working || model.status.busy || model.status.isActive }
  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      VStack(spacing: 8) {
        Image(systemName: model.status.isActive ? "cup.and.saucer.fill" : "cup.and.saucer")
          .font(.system(size: 28)).foregroundStyle(model.status.isActive ? .orange : .secondary)
        Text(
          model.status.isActive
            ? countdown(model.status.remainingSeconds) : "Take care of the work."
        )
        .font(.system(size: 25, weight: .medium, design: .rounded)).monospacedDigit()
        Text(
          model.status.isActive
            ? (model.status.mode?.title ?? "Session active")
            : "Your Mac will stay awake while you need it."
        )
        .font(.callout).foregroundStyle(.secondary)
      }.frame(maxWidth: .infinity).padding(.vertical, 8)
      Text("MODE").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
      Picker(
        "Mode",
        selection: Binding(get: { model.status.selectedMode }, set: { model.select(mode: $0) })
      ) {
        ForEach(Mode.allCases) { mode in Label(mode.title, systemImage: mode.symbol).tag(mode) }
      }.pickerStyle(.menu).labelsHidden().disabled(disabled)
      Text(model.status.selectedMode.detail).font(.caption).foregroundStyle(.secondary)
      Text("DURATION").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
      HStack {
        ForEach([1800, 3600, 7200, 14400, 0], id: \.self) { seconds in
          Button(seconds == 0 ? "∞" : seconds < 3600 ? "30m" : "\(seconds / 3600)h") {
            model.select(duration: .some(seconds == 0 ? nil : seconds))
          }.buttonStyle(.bordered).tint(
            model.status.selectedDuration == (seconds == 0 ? nil : seconds) ? .orange : .secondary
          )
          .disabled(disabled)
        }
      }
      DisclosureGroup("Custom duration") {
        HStack {
          TextField("Minutes", text: $customMinutes).textFieldStyle(.roundedBorder)
            .accessibilityLabel("Custom session duration in minutes")
          Button("Apply") {
            if let minutes = Int(customMinutes), minutes > 0, minutes <= 10080 {
              model.select(duration: .some(minutes * 60))
            } else {
              model.actionError = "Choose a duration between 1 minute and 7 days."
            }
          }
        }.padding(.top, 6)
      }.font(.caption).disabled(disabled)
      if let seconds = model.status.selectedDuration, ![1800, 3600, 7200, 14400].contains(seconds) {
        Text("Selected: \(countdown(seconds))").font(.caption).foregroundStyle(.secondary)
      }
      Button {
        model.toggle()
      } label: {
        Label(
          model.status.recoveryRequired
            ? "Restore sleep settings" : model.status.isActive ? "Stop session" : "Start session",
          systemImage: model.status.isActive ? "stop.fill" : "play.fill"
        )
        .frame(maxWidth: .infinity).padding(.vertical, 6)
      }.keyboardShortcut(.return, modifiers: .command).buttonStyle(.borderedProminent).tint(
        model.status.recoveryRequired ? .red : .orange
      )
      .disabled(model.working || model.status.busy)
      if model.status.selectedMode == .server {
        Text(
          "Server Mode changes the global sleep override and asks for administrator authorization. Keep ventilation clear with the lid closed. Your original setting is restored when the session stops."
        )
        .font(.caption).foregroundStyle(.secondary)
      }
    }
  }
}

struct PowerView: View {
  @ObservedObject var model: AppModel
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      if let error = model.telemetryError { Text(error).foregroundStyle(.secondary) }
      if let sample = model.telemetry {
        HStack {
          Label(
            sample.chargingState.replacingOccurrences(of: "_", with: " ").capitalized,
            systemImage: sample.chargingState == "battery" ? "battery.75percent" : "bolt.fill")
          Spacer()
          Text(sample.batteryPercent.map { String(format: "%.0f%%", $0) } ?? "Unavailable")
            .monospacedDigit()
        }.font(.headline)
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
          Metric(title: "System draw", value: watts(sample.systemWatts), symbol: "desktopcomputer")
          Metric(
            title: "Adapter input", value: watts(sample.adapterInputWatts), symbol: "powerplug")
          Metric(
            title: "Battery power", value: watts(sample.batteryWatts), symbol: "battery.75percent")
          Metric(title: "Charger rating", value: watts(sample.adapterRatingWatts), symbol: "bolt")
        }
        Text(
          "Hardware readings update every 2 seconds. Charger rating is capacity, not measured consumption. Positive battery power charges; negative discharges."
        )
        .font(.caption).foregroundStyle(.secondary)
        GroupBox("Battery details") {
          VStack(spacing: 9) {
            InfoRow(
              title: "Voltage",
              value: sample.batteryVoltage.map { String(format: "%.2f V", $0) } ?? "Unavailable")
            InfoRow(
              title: "Current",
              value: sample.batteryCurrentAmps.map { String(format: "%+.2f A", $0) }
                ?? "Unavailable")
            InfoRow(
              title: sample.chargingState == "charging" ? "Time to full" : "Time remaining",
              value: sample.timeRemainingMinutes.map { "\($0) min" } ?? "Unavailable")
          }.padding(8)
        }
      } else if model.telemetryError == nil {
        ProgressView("Reading power sensors…")
      }
      if let profile = model.profile {
        GroupBox("Sleep settings") {
          VStack(spacing: 9) {
            InfoRow(title: "Power source", value: profile.source)
            InfoRow(title: "Display sleep", value: sleepTimer(profile.displaySleep))
            InfoRow(title: "Disk sleep", value: sleepTimer(profile.diskSleep))
            InfoRow(title: "System sleep", value: sleepTimer(profile.systemSleep))
            InfoRow(
              title: "Global sleep override", value: profile.sleepDisabled ? "Enabled" : "Off")
            if !profile.preventedBy.isEmpty {
              Text("Sleep prevented by \(profile.preventedBy.joined(separator: ", "))").font(
                .caption
              ).foregroundStyle(.secondary)
            }
          }.padding(8)
        }
        if !profile.assertions.isEmpty {
          GroupBox("Active assertions") {
            VStack(alignment: .leading, spacing: 8) {
              ForEach(Array(profile.assertions.enumerated()), id: \.offset) { _, assertion in
                Text(assertion).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
              }
            }.padding(8).frame(maxWidth: .infinity, alignment: .leading)
          }
        }
      }
    }
  }
}
struct HistoryView: View {
  @ObservedObject var model: AppModel
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Picker("History range", selection: $model.historyRange) {
        ForEach(HistoryRange.allCases) { Text($0.title).tag($0) }
      }.pickerStyle(.segmented).onChange(of: model.historyRange) { _ in model.refresh() }
      if let error = model.historyError { Text(error).foregroundStyle(.red) }
      HStack {
        Metric(
          title: "Average draw", value: watts(model.history.averageSystemWatts),
          symbol: "waveform.path")
        Metric(title: "Peak draw", value: watts(model.history.peakSystemWatts), symbol: "bolt.fill")
      }
      if model.history.points.contains(where: { $0.systemWatts != nil }) {
        Chart(model.history.points) { point in
          if let watts = point.systemWatts {
            LineMark(x: .value("Time", point.date), y: .value("Watts", watts)).foregroundStyle(
              .orange)
          }
        }.chartYAxisLabel("Watts").frame(height: 160)
          .accessibilityLabel("System power history")
      } else {
        empty(
          "No system power readings yet",
          detail: "History is saved every 30 seconds when your Mac exposes the sensor.")
      }
      if model.history.points.contains(where: { $0.batteryPercent != nil }) {
        Text("BATTERY LEVEL").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
        Chart(model.history.points) { point in
          if let percent = point.batteryPercent {
            LineMark(x: .value("Time", point.date), y: .value("Battery", percent)).foregroundStyle(
              .green)
          }
        }.chartYScale(domain: 0...100).chartYAxisLabel("Percent").frame(height: 100)
          .accessibilityLabel("Battery level history")
      }
      InfoRow(title: "Time kept awake", value: countdown(model.history.sessionSeconds))
      Text("RECENT SESSIONS").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
      if model.history.sessions.isEmpty {
        empty("No sessions in this range", detail: "Start a session to see it here.")
      }
      ForEach(model.history.sessions) { session in
        HStack(alignment: .top, spacing: 12) {
          Image(systemName: session.mode.symbol).foregroundStyle(.orange)
          VStack(alignment: .leading, spacing: 4) {
            Text(session.mode.title).font(.callout.weight(.medium))
            Text(Date(timeIntervalSince1970: Double(session.startedAtMS) / 1000), style: .date)
              .font(.caption).foregroundStyle(.secondary)
          }
          Spacer()
          VStack(alignment: .trailing, spacing: 4) {
            Text(session.endReason?.capitalized ?? "Active").font(.caption)
            Text(Date(timeIntervalSince1970: Double(session.startedAtMS) / 1000), style: .time)
              .font(.caption).foregroundStyle(.secondary)
          }
        }.padding(12).background(
          Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
      }
    }
  }
  private func empty(_ title: String, detail: String) -> some View {
    VStack(spacing: 8) {
      Image(systemName: "chart.xyaxis.line").font(.title2)
      Text(title).font(.callout)
      Text(detail).font(.caption)
    }
    .foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(20)
  }
}
struct SettingsView: View {
  @ObservedObject var model: AppModel
  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      GroupBox("Startup") {
        Toggle(
          "Launch at login",
          isOn: Binding(
            get: { model.isPreview ? false : model.loginEnabled }, set: { model.setLogin($0) })
        ).padding(10)
      }
      GroupBox("Your data") {
        VStack(alignment: .leading, spacing: 10) {
          Text(
            "Settings and session history stay on this Mac. Power samples are retained for 7 days."
          ).font(.callout)
          Button("Open data folder") { NSWorkspace.shared.open(model.engine.storage.directory) }
        }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
      }
      GroupBox("Raycast") {
        Text(
          "Open, start, stop, and toggle sessions using the Caffeinator extension. The local control service is available while this app is running."
        )
        .font(.callout).padding(10)
      }
      HStack {
        VStack(alignment: .leading, spacing: 4) {
          Text("Caffeinator").font(.headline)
          Text(
            "Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development")"
          ).font(.caption).foregroundStyle(.secondary)
        }
        Spacer()
        Link("GitHub", destination: URL(string: "https://github.com/tasnimzotder/caffeinator")!)
      }
    }
  }
}
struct Metric: View {
  var title: String
  var value: String
  var symbol: String
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Label(title, systemImage: symbol).font(.caption).foregroundStyle(.secondary)
      Text(value).font(.system(size: 23, weight: .medium, design: .rounded)).monospacedDigit()
        .minimumScaleFactor(0.7)
    }.padding(14).frame(maxWidth: .infinity, alignment: .leading).background(
      Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
  }
}
struct InfoRow: View {
  var title: String
  var value: String
  var body: some View {
    HStack {
      Text(title).foregroundStyle(.secondary)
      Spacer()
      Text(value).monospacedDigit()
    }.font(.callout)
  }
}
func watts(_ value: Double?) -> String {
  value.map { String(format: "%.1f W", $0) } ?? "Unavailable"
}
func sleepTimer(_ value: Int?) -> String {
  value.map { $0 == 0 ? "Never" : "\($0) min" } ?? "Unavailable"
}
func countdown(_ seconds: Int?) -> String {
  guard let seconds else { return "Until stopped" }
  let hours = seconds / 3600
  let minutes = seconds % 3600 / 60
  let remaining = seconds % 60
  return hours > 0
    ? String(format: "%d:%02d:%02d", hours, minutes, remaining)
    : String(format: "%02d:%02d", minutes, remaining)
}
