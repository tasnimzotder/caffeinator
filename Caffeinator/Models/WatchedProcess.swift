import Foundation
import AppKit

struct WatchedProcess: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var bundleIdentifier: String?
    var isBuiltIn: Bool
    
    init(id: UUID = UUID(), name: String, bundleIdentifier: String? = nil, isBuiltIn: Bool = false) {
        self.id = id
        self.name = name
        self.bundleIdentifier = bundleIdentifier
        self.isBuiltIn = isBuiltIn
    }
    
    static var defaultWatchList: [WatchedProcess] {
        [
            // IDEs & Editors
            WatchedProcess(name: "Xcode", bundleIdentifier: "com.apple.dt.Xcode", isBuiltIn: true),
            WatchedProcess(name: "Visual Studio Code", bundleIdentifier: "com.microsoft.VSCode", isBuiltIn: true),
            WatchedProcess(name: "Cursor", bundleIdentifier: "com.todesktop.230313mzl4w4u92", isBuiltIn: true),
            WatchedProcess(name: "Zed", bundleIdentifier: "dev.zed.Zed", isBuiltIn: true),
            
            // JetBrains IDEs
            WatchedProcess(name: "IntelliJ IDEA", bundleIdentifier: "com.jetbrains.intellij", isBuiltIn: true),
            WatchedProcess(name: "WebStorm", bundleIdentifier: "com.jetbrains.WebStorm", isBuiltIn: true),
            WatchedProcess(name: "PyCharm", bundleIdentifier: "com.jetbrains.pycharm", isBuiltIn: true),
            WatchedProcess(name: "GoLand", bundleIdentifier: "com.jetbrains.goland", isBuiltIn: true),
            WatchedProcess(name: "CLion", bundleIdentifier: "com.jetbrains.CLion", isBuiltIn: true),
            WatchedProcess(name: "RubyMine", bundleIdentifier: "com.jetbrains.rubymine", isBuiltIn: true),
            WatchedProcess(name: "DataGrip", bundleIdentifier: "com.jetbrains.datagrip", isBuiltIn: true),
            
            // Terminals
            WatchedProcess(name: "Terminal", bundleIdentifier: "com.apple.Terminal", isBuiltIn: true),
            WatchedProcess(name: "iTerm2", bundleIdentifier: "com.googlecode.iterm2", isBuiltIn: true),
            WatchedProcess(name: "Warp", bundleIdentifier: "dev.warp.Warp-Stable", isBuiltIn: true),
            WatchedProcess(name: "Alacritty", bundleIdentifier: "org.alacritty", isBuiltIn: true),
            WatchedProcess(name: "Kitty", bundleIdentifier: "net.kovidgoyal.kitty", isBuiltIn: true),
            
            // Build Tools & Containers
            WatchedProcess(name: "Docker", bundleIdentifier: "com.docker.docker", isBuiltIn: true),
            WatchedProcess(name: "Podman", bundleIdentifier: "com.redhat.podman-desktop", isBuiltIn: true),
            
            // Virtual Machines
            WatchedProcess(name: "Parallels Desktop", bundleIdentifier: "com.parallels.desktop.console", isBuiltIn: true),
            WatchedProcess(name: "VMware Fusion", bundleIdentifier: "com.vmware.fusion", isBuiltIn: true),
            WatchedProcess(name: "UTM", bundleIdentifier: "com.utmapp.UTM", isBuiltIn: true),
            WatchedProcess(name: "VirtualBox", bundleIdentifier: "org.virtualbox.app.VirtualBox", isBuiltIn: true),
            
            // Design Tools
            WatchedProcess(name: "Figma", bundleIdentifier: "com.figma.Desktop", isBuiltIn: true),
            WatchedProcess(name: "Sketch", bundleIdentifier: "com.bohemiancoding.sketch3", isBuiltIn: true),
            
            // Video/Streaming
            WatchedProcess(name: "OBS", bundleIdentifier: "com.obsproject.obs-studio", isBuiltIn: true),
            WatchedProcess(name: "Zoom", bundleIdentifier: "us.zoom.xos", isBuiltIn: true),
        ]
    }
}
