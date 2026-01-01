import Foundation

enum Duration: Hashable, Identifiable {
    case thirtyMinutes
    case oneHour
    case twoHours
    case fourHours
    case indefinite
    case custom(seconds: Int)
    
    var id: String {
        switch self {
        case .thirtyMinutes: return "30m"
        case .oneHour: return "1h"
        case .twoHours: return "2h"
        case .fourHours: return "4h"
        case .indefinite: return "indefinite"
        case .custom(let s): return "custom-\(s)"
        }
    }
    
    var seconds: Int? {
        switch self {
        case .thirtyMinutes: return 30 * 60
        case .oneHour: return 60 * 60
        case .twoHours: return 2 * 60 * 60
        case .fourHours: return 4 * 60 * 60
        case .indefinite: return nil
        case .custom(let s): return s
        }
    }
    
    var displayName: String {
        switch self {
        case .thirtyMinutes: return "30 minutes"
        case .oneHour: return "1 hour"
        case .twoHours: return "2 hours"
        case .fourHours: return "4 hours"
        case .indefinite: return "Indefinitely"
        case .custom(let s): return Duration.formatSeconds(s)
        }
    }
    
    var shortName: String {
        switch self {
        case .thirtyMinutes: return "30m"
        case .oneHour: return "1h"
        case .twoHours: return "2h"
        case .fourHours: return "4h"
        case .indefinite: return "∞"
        case .custom(let s): return Duration.formatSecondsShort(s)
        }
    }
    
    static var presets: [Duration] {
        [.thirtyMinutes, .oneHour, .twoHours, .fourHours, .indefinite]
    }
    
    static func formatSeconds(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        if hours > 0 && minutes > 0 {
            return "\(hours)h \(minutes)m"
        } else if hours > 0 {
            return "\(hours) hour\(hours > 1 ? "s" : "")"
        } else {
            return "\(minutes) minute\(minutes > 1 ? "s" : "")"
        }
    }
    
    static func formatSecondsShort(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        if hours > 0 && minutes > 0 {
            return "\(hours)h\(minutes)m"
        } else if hours > 0 {
            return "\(hours)h"
        } else {
            return "\(minutes)m"
        }
    }
    
    static func from(id: String) -> Duration? {
        switch id {
        case "30m": return .thirtyMinutes
        case "1h": return .oneHour
        case "2h": return .twoHours
        case "4h": return .fourHours
        case "indefinite": return .indefinite
        default:
            if id.hasPrefix("custom-"), let seconds = Int(id.dropFirst(7)) {
                return .custom(seconds: seconds)
            }
            return nil
        }
    }
}
