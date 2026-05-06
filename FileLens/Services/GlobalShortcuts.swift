import AppKit
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// Brings the FileLens window to the front from anywhere on the system.
    static let openWindow = Self("openWindow")
}

enum GlobalShortcuts {
    /// Wire up handlers once at app launch. The recorder UI in Settings
    /// edits the same KeyboardShortcuts default, so users can rebind without
    /// touching code.
    static func register() {
        KeyboardShortcuts.onKeyDown(for: .openWindow) {
            activateMainWindow()
        }
    }

    private static func activateMainWindow() {
        NSApp.activate(ignoringOtherApps: true)

        // Pick the WindowGroup-backed main window. Filter out:
        //  - NSPanel subclasses (the toast overlay, popovers)
        //  - the Settings window — its identifier is
        //    "com_apple_SwiftUI_Settings_window" on macOS 14+
        //  - any window that can't become main
        // The previous logic just took `.windows.first`, which on a freshly
        // configured shortcut returns Settings (it's the active window).
        let main = NSApp.windows.first { window in
            guard !(window is NSPanel), window.canBecomeMain else { return false }
            let id = window.identifier?.rawValue.lowercased() ?? ""
            return !id.contains("settings") && !id.contains("preference")
        }

        if let main {
            main.deminiaturize(nil)        // restore from Dock if minimized
            main.makeKeyAndOrderFront(nil)
        }
    }
}
