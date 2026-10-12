import Foundation

/// Stores RichTextEditorController instances by DashboardModuleModel.id so
/// text module views survive remounts without re-initializing the editor.
final class TextEditorControllerStore {
    static let shared = TextEditorControllerStore()
    private init() {}

    #if os(macOS)
    private var cache: [UUID: RichTextEditorController] = [:]

    func controller(for moduleId: UUID) -> RichTextEditorController {
        if let existing = cache[moduleId] { return existing }
        let controller = RichTextEditorController()
        cache[moduleId] = controller
        return controller
    }
    #endif

    func evict(_ moduleId: UUID) {
        #if os(macOS)
        cache.removeValue(forKey: moduleId)
        #endif
    }
}
