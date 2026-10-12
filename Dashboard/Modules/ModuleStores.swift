import Foundation

/// Single call site for evicting all per-type module service stores when a module
/// is permanently deleted from the document.
enum ModuleStores {
    static func evict(_ moduleId: UUID) {
        TextEditorControllerStore.shared.evict(moduleId)
        DAWTransportViewModelStore.shared.evict(moduleId)
    }
}
