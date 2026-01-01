import Foundation

/// A customizable timer preset
struct TimerPreset: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var minutes: Int
    var isDefault: Bool
    
    init(id: UUID = UUID(), name: String, minutes: Int, isDefault: Bool = false) {
        self.id = id
        self.name = name
        self.minutes = minutes
        self.isDefault = isDefault
    }
    
    var seconds: Int {
        minutes * 60
    }
    
    var duration: Duration {
        if minutes == 0 {
            return .indefinite
        }
        return .custom(seconds: seconds)
    }
    
    var displayName: String {
        if minutes == 0 {
            return "Indefinite"
        }
        let hours = minutes / 60
        let mins = minutes % 60
        if hours > 0 && mins > 0 {
            return "\(hours)h \(mins)m"
        } else if hours > 0 {
            return "\(hours) hour\(hours > 1 ? "s" : "")"
        } else {
            return "\(mins) minute\(mins > 1 ? "s" : "")"
        }
    }
    
    var shortName: String {
        if minutes == 0 {
            return "∞"
        }
        let hours = minutes / 60
        let mins = minutes % 60
        if hours > 0 && mins > 0 {
            return "\(hours)h\(mins)m"
        } else if hours > 0 {
            return "\(hours)h"
        } else {
            return "\(mins)m"
        }
    }
    
    // Default presets
    static let defaults: [TimerPreset] = [
        TimerPreset(name: "30 minutes", minutes: 30, isDefault: true),
        TimerPreset(name: "1 hour", minutes: 60, isDefault: true),
        TimerPreset(name: "2 hours", minutes: 120, isDefault: true),
        TimerPreset(name: "4 hours", minutes: 240, isDefault: true),
        TimerPreset(name: "Indefinite", minutes: 0, isDefault: true)
    ]
}
