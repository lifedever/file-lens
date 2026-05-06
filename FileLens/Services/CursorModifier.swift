import SwiftUI
import AppKit

extension View {
    /// Switches the cursor to a pointing hand on hover. The push/pop pair can
    /// stack incorrectly if hover events fire faster than they unwind, but
    /// it's the simplest approach that works without a full NSViewRepresentable.
    func pointingHandCursor() -> some View {
        self.onHover { hovering in
            if hovering { NSCursor.pointingHand.push() }
            else        { NSCursor.pop() }
        }
    }
}
