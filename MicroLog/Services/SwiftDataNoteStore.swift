import Foundation
import SwiftData
import SwiftUI

@MainActor
final class SwiftDataNoteStore: NoteStore {
    private let context: ModelContext

    init(context: ModelContext) { self.context = context }

    var notes: [Note] {
        let descriptor = FetchDescriptor<Note>(sortBy: [SortDescriptor(\.capturedAt, order: .reverse)])
        return (try? context.fetch(descriptor)) ?? []
    }

    func add(_ note: Note) { context.insert(note); try? context.save() }
    func update(_ note: Note) { try? context.save() }
    func delete(_ note: Note) { context.delete(note); try? context.save() }

    func todayNotes() -> [Note] {
        let (s, e) = Note.todayRange()
        let descriptor = FetchDescriptor<Note>(
            predicate: #Predicate { $0.capturedAt >= s && $0.capturedAt < e },
            sortBy: [SortDescriptor(\.capturedAt, order: .reverse)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    func allNotes() -> [Note] { notes }
}
