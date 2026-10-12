import SwiftUI
import Combine
#if os(macOS)
import AppKit
#endif

final class ModifierTracker: ObservableObject {
    static let shared = ModifierTracker()
    @Published var isModifierPressed: Bool = false
    
    private var monitor: Any?
    
    private init() {
        #if os(macOS)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            if self?.isModifierPressed != event.modifierFlags.contains(.option) {
                self?.isModifierPressed = event.modifierFlags.contains(.option)
            }
            return event
        }
        #endif
    }
    
    deinit {
        #if os(macOS)
        if let monitor = monitor {
            NSEvent.removeMonitor(monitor)
        }
        #endif
    }
}
