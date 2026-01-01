import Foundation

/// Pre-configured settings for common developer workflows
struct DeveloperPreset: Identifiable, Hashable {
    let id: String
    let name: String
    let icon: String
    let duration: Duration
    let modes: Set<CaffeinateMode>
    let description: String
    
    static let all: [DeveloperPreset] = [
        DeveloperPreset(
            id: "docker",
            name: "Docker Build",
            icon: "shippingbox.fill",
            duration: .fourHours,
            modes: [.idle, .disk],
            description: "Container builds & pulls"
        ),
        DeveloperPreset(
            id: "xcode",
            name: "Xcode Build",
            icon: "hammer.fill",
            duration: .twoHours,
            modes: [.idle, .disk],
            description: "iOS/macOS compilation"
        ),
        DeveloperPreset(
            id: "npm",
            name: "npm/pnpm Install",
            icon: "arrow.down.circle.fill",
            duration: .oneHour,
            modes: [.idle],
            description: "Package installation"
        ),
        DeveloperPreset(
            id: "deploy",
            name: "Deployment",
            icon: "icloud.and.arrow.up.fill",
            duration: .indefinite,
            modes: [.idle, .system],
            description: "CI/CD & deployments"
        ),
        DeveloperPreset(
            id: "presentation",
            name: "Presentation",
            icon: "play.rectangle.fill",
            duration: .indefinite,
            modes: [.display, .idle],
            description: "Meetings & demos"
        ),
        DeveloperPreset(
            id: "ml",
            name: "ML Training",
            icon: "brain",
            duration: .indefinite,
            modes: [.idle, .system, .disk],
            description: "Long-running computations"
        )
    ]
}
