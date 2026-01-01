import SwiftUI
import AppKit

// MARK: - Settings Helper

enum SettingsHelper {
    @MainActor
    static func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        
        DispatchQueue.main.async {
            // Find and click the Settings menu item
            if let mainMenu = NSApp.mainMenu {
                // Look for the app menu (first item)
                if let appMenu = mainMenu.items.first?.submenu {
                    // Find Settings/Preferences item
                    for item in appMenu.items {
                        let title = item.title.lowercased()
                        if title.contains("settings") || title.contains("preferences") {
                            _ = item.target?.perform(item.action, with: item)
                            return
                        }
                    }
                }
            }
            
            // Fallback to selector
            if #available(macOS 14.0, *) {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            } else {
                NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
            }
        }
    }
}

// MARK: - Spacing

enum Spacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 20
    static let xxl: CGFloat = 24
}

// MARK: - Corner Radius

enum CornerRadius {
    static let sm: CGFloat = 6
    static let md: CGFloat = 8
    static let lg: CGFloat = 12
}

// MARK: - Animation

enum AppAnimation {
    static let fast: Double = 0.15
    static let standard: Double = 0.25
    static let slow: Double = 0.4
    
    static var spring: Animation {
        .spring(response: 0.3, dampingFraction: 0.7)
    }
    
    static var snappy: Animation {
        .spring(response: 0.2, dampingFraction: 0.8)
    }
}

// MARK: - Layout

enum Layout {
    static let menuBarWidth: CGFloat = 280
    static let settingsWidth: CGFloat = 500
    static let settingsHeight: CGFloat = 380
}

// MARK: - Time Formatter

enum TimeFormat {
    /// Formats seconds into human-readable string
    /// - Parameters:
    ///   - seconds: Total seconds
    ///   - style: Format style
    /// - Returns: Formatted string
    static func format(_ seconds: Int, style: Style = .standard) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        
        switch style {
        case .standard:
            if h > 0 {
                return String(format: "%d:%02d:%02d", h, m, s)
            }
            return String(format: "%d:%02d", m, s)
            
        case .compact:
            if h > 0 {
                return "\(h):\(String(format: "%02d", m))"
            }
            return "\(m)m"
            
        case .verbose:
            if h > 0 && m > 0 {
                return "\(h)h \(m)m"
            } else if h > 0 {
                return "\(h) hour\(h > 1 ? "s" : "")"
            } else if m > 0 {
                return "\(m) minute\(m > 1 ? "s" : "")"
            } else {
                return "\(s) second\(s > 1 ? "s" : "")"
            }
            
        case .remaining:
            if h > 0 {
                return String(format: "%d:%02d:%02d", h, m, s) + " remaining"
            }
            return String(format: "%d:%02d", m, s) + " remaining"
        }
    }
    
    enum Style {
        case standard   // "2:45:30" or "45:30"
        case compact    // "2:45" or "45m"
        case verbose    // "2 hours 45 minutes"
        case remaining  // "2:45:30 remaining"
    }
}

// MARK: - View Modifiers

extension View {
    /// Applies card styling with subtle background and shadow
    func cardStyle() -> some View {
        self
            .padding(Spacing.md)
            .background(.background.secondary)
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md))
    }
    
    /// Applies pill styling for tags/badges
    func pillStyle(isActive: Bool = false) -> some View {
        self
            .font(.caption)
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .background(isActive ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.1))
            .foregroundStyle(isActive ? Color.accentColor : .secondary)
            .clipShape(Capsule())
    }
    
    /// Section header styling
    func sectionHeader() -> some View {
        self
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
    }
    
    /// Hover effect for interactive elements
    func hoverEffect() -> some View {
        self.modifier(HoverEffectModifier())
    }
}

// MARK: - Hover Effect Modifier

struct HoverEffectModifier: ViewModifier {
    @State private var isHovered = false
    
    func body(content: Content) -> some View {
        content
            .brightness(isHovered ? 0.05 : 0)
            .animation(.easeInOut(duration: AppAnimation.fast), value: isHovered)
            .onHover { hovering in
                isHovered = hovering
            }
    }
}

// MARK: - Button Styles

struct QuickActionButtonStyle: ButtonStyle {
    let isSelected: Bool
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .frame(maxWidth: .infinity)
            .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.1))
            .foregroundStyle(isSelected ? .white : .primary)
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.sm))
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(AppAnimation.snappy, value: configuration.isPressed)
    }
}

struct ModeButtonStyle: ButtonStyle {
    let isSelected: Bool
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption.weight(.medium))
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .background(isSelected ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.08))
            .foregroundStyle(isSelected ? Color.accentColor : .secondary)
            .clipShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .animation(AppAnimation.snappy, value: configuration.isPressed)
    }
}

// MARK: - Status Indicator

struct StatusIndicator: View {
    let isActive: Bool
    
    var body: some View {
        Circle()
            .fill(isActive ? Color.green : Color.secondary.opacity(0.4))
            .frame(width: 8, height: 8)
            .shadow(color: isActive ? .green.opacity(0.5) : .clear, radius: 4)
    }
}
