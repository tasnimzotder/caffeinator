import Carbon
import AppKit
import Combine

/// Manages global keyboard shortcuts for the application
class GlobalShortcutManager: ObservableObject {
    static let shared = GlobalShortcutManager()
    
    @Published var isRegistered = false
    
    private var eventHandler: EventHandlerRef?
    private var hotKeyRef: EventHotKeyRef?
    private var callback: (() -> Void)?
    
    private init() {}
    
    /// Register the global hotkey (Cmd+Shift+C)
    func register(callback: @escaping () -> Void) {
        // Unregister any existing hotkey first
        unregister()
        
        self.callback = callback
        
        // Set up the event handler
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        
        // Store weak reference to self for the callback
        let userData = Unmanaged.passUnretained(self).toOpaque()
        
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, event, userData) -> OSStatus in
                guard let userData = userData else { return OSStatus(eventNotHandledErr) }
                let manager = Unmanaged<GlobalShortcutManager>.fromOpaque(userData).takeUnretainedValue()
                manager.callback?()
                return noErr
            },
            1,
            &eventType,
            userData,
            &eventHandler
        )
        
        guard status == noErr else {
            print("Failed to install event handler: \(status)")
            return
        }
        
        // Register the hotkey: Cmd+Shift+C
        // Key code 8 = 'C'
        // cmdKey = 256, shiftKey = 512
        var hotKeyID = EventHotKeyID(
            signature: OSType(0x4341_4646), // "CAFF"
            id: 1
        )
        
        let registerStatus = RegisterEventHotKey(
            UInt32(kVK_ANSI_C),
            UInt32(cmdKey | shiftKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        
        if registerStatus == noErr {
            isRegistered = true
            print("Global shortcut registered: Cmd+Shift+C")
        } else {
            print("Failed to register hotkey: \(registerStatus)")
        }
    }
    
    /// Unregister the global hotkey
    func unregister() {
        if let hotKeyRef = hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        
        if let eventHandler = eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
        
        isRegistered = false
        callback = nil
    }
    
    deinit {
        unregister()
    }
}

// MARK: - Shortcut Display Helper

extension GlobalShortcutManager {
    /// Returns a human-readable string for the current shortcut
    var shortcutDisplayString: String {
        "⌘⇧C"
    }
}
