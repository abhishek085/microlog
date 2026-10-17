import Foundation
import SwiftData

@MainActor
protocol NoteStore {
    var notes: [Note] { get }
    func add(_ note: Note)
    func update(_ note: Note)
    func delete(_ note: Note)
    func todayNotes() -> [Note]
    func allNotes() -> [Note]
}
