import Foundation

@MainActor
final class AppViewModel: ObservableObject {
    @Published var isSidebarVisible = false
    @Published var isSearchVisible = false
    @Published var searchQuery = ""
    @Published var searchSelection = 0
    @Published var isPinned: Bool
    @Published var shortcutError: String?
    @Published var editorFocusGeneration = 0
    @Published var searchFocusGeneration = 0
    @Published var pendingDeletionID: UUID?
    @Published var isFormatPaletteVisible = false
    @Published var isCollapsed = false
    @Published var isCollapseAnimating = false

    init(isPinned: Bool) {
        self.isPinned = isPinned
    }

    func focusEditor() {
        editorFocusGeneration &+= 1
    }

    func showSearch() {
        searchQuery = ""
        searchSelection = 0
        isSearchVisible = true
        searchFocusGeneration &+= 1
    }

    func closeSearch() {
        isSearchVisible = false
        searchQuery = ""
        searchSelection = 0
        focusEditor()
    }

    func requestDeletion(of id: UUID) {
        pendingDeletionID = id
    }

    func cancelDeletion() {
        pendingDeletionID = nil
    }
}
