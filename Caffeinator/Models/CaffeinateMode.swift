import Foundation

enum CaffeinateMode: String, CaseIterable, Identifiable, Codable {
    case display = "-d"  // Prevent display sleep
    case idle = "-i"     // Prevent idle sleep
    case system = "-s"   // Prevent system sleep (AC only)
    case disk = "-m"     // Prevent disk idle sleep
    
    var id: String { rawValue }
    
    var name: String {
        switch self {
        case .display: return "Display"
        case .idle: return "Idle"
        case .system: return "System"
        case .disk: return "Disk"
        }
    }
    
    var description: String {
        switch self {
        case .display: return "Prevent display from sleeping"
        case .idle: return "Prevent system from idle sleeping"
        case .system: return "Prevent system sleep (AC power only)"
        case .disk: return "Prevent disk from idle sleeping"
        }
    }
    
    var flag: String { rawValue }
}
