import Foundation
import QuickNotesCore

struct NotesStoreSnapshot: Equatable {
    let notes: [QuickNote]
    let selectedNoteID: UUID?
}

struct NoteDeletionRecord: Equatable {
    let note: QuickNote
    let originalIndex: Int
    let selectedNoteIDBeforeDeletion: UUID?
    let generatedReplacementNoteID: UUID?
}

@MainActor
final class NotesStore: ObservableObject {
    private let repository: NotesRepository
    private let defaults: UserDefaults
    private var pendingSave: DispatchWorkItem?
    private var savingBlockedByLoadError = false

    @Published private(set) var notes: [QuickNote] = []
    @Published var selectedNoteID: UUID?
    @Published var storageError: String?

    init(repository: NotesRepository, defaults: UserDefaults = .standard) {
        self.repository = repository
        self.defaults = defaults

        do {
            notes = try repository.load()
        } catch {
            notes = []
            savingBlockedByLoadError = true
            storageError = "Notes could not be loaded. The original file was left unchanged."
        }

        if notes.isEmpty {
            notes = [QuickNote()]
        }

        if let storedID = defaults.string(forKey: "selectedNoteID").flatMap(UUID.init),
           notes.contains(where: { $0.id == storedID }) {
            selectedNoteID = storedID
        } else {
            selectedNoteID = sortedNotes.first?.id
        }
    }

    var sortedNotes: [QuickNote] {
        notes.sorted { $0.modifiedAt > $1.modifiedAt }
    }

    var selectedNote: QuickNote? {
        guard let selectedNoteID else { return nil }
        return notes.first { $0.id == selectedNoteID }
    }

    func updateSelectedText(_ text: String) {
        updateSelectedContent(text: text, richTextData: nil)
    }

    func updateSelectedContent(text: String, richTextData: Data?) {
        guard let selectedNoteID,
              let index = notes.firstIndex(where: { $0.id == selectedNoteID }),
              notes[index].text != text || notes[index].richTextData != richTextData else { return }
        notes[index].text = text
        notes[index].richTextData = richTextData
        notes[index].modifiedAt = Date()
        scheduleSave()
    }

    func select(_ id: UUID) {
        guard notes.contains(where: { $0.id == id }) else { return }
        flush()
        selectedNoteID = id
        defaults.set(id.uuidString, forKey: "selectedNoteID")
    }

    @discardableResult
    func createNote() -> UUID {
        flush()
        let note = QuickNote()
        notes.append(note)
        select(note.id)
        scheduleSave()
        return note.id
    }

    @discardableResult
    func duplicate(_ id: UUID) -> UUID? {
        guard let source = notes.first(where: { $0.id == id }) else { return nil }
        flush()
        let now = Date()
        let copy = QuickNote(
            text: source.text,
            richTextData: source.richTextData,
            createdAt: now,
            modifiedAt: now
        )
        notes.append(copy)
        select(copy.id)
        scheduleSave()
        return copy.id
    }

    func searchResults(for query: String) -> [QuickNote] {
        sortedNotes.filter { $0.matches(query) }
    }

    func snapshot() -> NotesStoreSnapshot {
        NotesStoreSnapshot(notes: notes, selectedNoteID: selectedNoteID)
    }

    @discardableResult
    func delete(_ id: UUID) -> Bool {
        deleteRecording(id) != nil
    }

    @discardableResult
    func deleteRecording(_ id: UUID) -> NoteDeletionRecord? {
        guard let originalIndex = notes.firstIndex(where: { $0.id == id }) else { return nil }
        let note = notes[originalIndex]
        let selectedNoteIDBeforeDeletion = selectedNoteID
        flush()
        notes.removeAll { $0.id == id }

        var generatedReplacementNoteID: UUID?
        if notes.isEmpty {
            let replacement = QuickNote()
            notes = [replacement]
            selectedNoteID = replacement.id
            generatedReplacementNoteID = replacement.id
        } else if selectedNoteID == id {
            selectedNoteID = sortedNotes.first?.id
        }

        if let selectedNoteID {
            defaults.set(selectedNoteID.uuidString, forKey: "selectedNoteID")
        } else {
            defaults.removeObject(forKey: "selectedNoteID")
        }
        scheduleSave()
        return NoteDeletionRecord(
            note: note,
            originalIndex: originalIndex,
            selectedNoteIDBeforeDeletion: selectedNoteIDBeforeDeletion,
            generatedReplacementNoteID: generatedReplacementNoteID
        )
    }

    func restoreDeletion(_ record: NoteDeletionRecord) {
        guard !notes.contains(where: { $0.id == record.note.id }) else { return }
        flush()
        if let replacementID = record.generatedReplacementNoteID {
            notes.removeAll { $0.id == replacementID }
        }
        notes.insert(record.note, at: min(record.originalIndex, notes.count))
        if let previousSelection = record.selectedNoteIDBeforeDeletion,
           notes.contains(where: { $0.id == previousSelection }) {
            selectedNoteID = previousSelection
        } else {
            selectedNoteID = record.note.id
        }
        if let selectedNoteID {
            defaults.set(selectedNoteID.uuidString, forKey: "selectedNoteID")
        }
        scheduleSave()
    }

    func restore(_ snapshot: NotesStoreSnapshot) {
        pendingSave?.cancel()
        pendingSave = nil
        notes = snapshot.notes.isEmpty ? [QuickNote()] : snapshot.notes
        if let requested = snapshot.selectedNoteID,
           notes.contains(where: { $0.id == requested }) {
            selectedNoteID = requested
        } else {
            selectedNoteID = sortedNotes.first?.id
        }
        if let selectedNoteID {
            defaults.set(selectedNoteID.uuidString, forKey: "selectedNoteID")
        }
        saveNow()
    }

    func flush() {
        pendingSave?.cancel()
        pendingSave = nil
        saveNow()
    }

    private func scheduleSave() {
        pendingSave?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.saveNow()
        }
        pendingSave = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: workItem)
    }

    private func saveNow() {
        guard !savingBlockedByLoadError else { return }
        do {
            try repository.save(notes)
            storageError = nil
        } catch {
            storageError = "Changes could not be saved. Check disk space and permissions."
        }
    }
}
