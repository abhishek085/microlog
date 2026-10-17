import Foundation
import SwiftData
#if os(macOS)
import UserNotifications
#endif

@MainActor
final class ReadingCaptureService {
    private let provider: CaptureProvider
    private let embedding: any EmbeddingService
    private let summarizer: Summarizer
    private let store: NoteStore
    private let dedupe = DedupeEngine()
    private let context: ModelContext
    private var task: Task<Void, Never>?
    private let directiveProvider: () -> String
    private let onPill: (AmbientPillState) -> Void
    private let onNoteAdded: (NoteUI) -> Void
    private let onNoteUpdated: (NoteUI) -> Void
    private var pendingDuplicate: (ctx: CaptureContext, candidate: DedupeEngine.Candidate)?

    init(provider: CaptureProvider,
         embedding: (any EmbeddingService)? = nil,
         summarizer: Summarizer,
         store: NoteStore,
         context: ModelContext,
         directiveProvider: @escaping () -> String,
         onPill: @escaping (AmbientPillState) -> Void,
         onNoteAdded: @escaping (NoteUI) -> Void = { _ in },
         onNoteUpdated: @escaping (NoteUI) -> Void = { _ in }) {
        self.provider = provider
        self.embedding = embedding ?? PlaceholderEmbeddingService()
        self.summarizer = summarizer
        self.store = store
        self.context = context
        self.directiveProvider = directiveProvider
        self.onPill = onPill
        self.onNoteAdded = onNoteAdded
        self.onNoteUpdated = onNoteUpdated
    }

    func start() {
        task = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .seconds(5))
            while !Task.isCancelled {
                await self.tick()
                try? await Task.sleep(for: .seconds(12))
            }
        }
    }

    func stop() { task?.cancel() }

    func captureOne() async { await tick() }

    /// Forces the most recently collapsed duplicate/thread capture to be saved as a brand-new note.
    func saveAsNewFromPending() {
        guard let pending = pendingDuplicate else { return }
        pendingDuplicate = nil
        let note = makeNote(from: pending.ctx, candidate: pending.candidate)
        store.add(note)
        onNoteAdded(noteUI(from: note))
        summarizeInBackground(note, context: pending.ctx)
    }

    private func tick() async {
        guard let ctx = try? await provider.currentContext() else { return }
        guard ctx.wordCount >= 150 else { return }
        guard !ctx.isPrivate else { return }

        let candidate = await DedupeEngine.makeCandidate(from: ctx, embeddingService: embedding)
        let all = store.allNotes()
        let decision = dedupe.evaluate(candidate: candidate, against: all)

        switch decision {
        case .duplicate(let existing):
            existing.lastSeenAt = Date()
            existing.seenCount += 1
            // Move to top among today's by bumping capturedAt.
            existing.capturedAt = Date()
            store.update(existing)
            onNoteUpdated(noteUI(from: existing))
            pendingDuplicate = (ctx, candidate)
            onPill(AmbientPillState(kind: .duplicate, title: existing.title, noteID: existing.id))

        case .related(let existing, _):
            let note = makeNote(from: ctx, candidate: candidate)
            note.relatedNoteIDs.append(existing.id)
            store.add(note)
            onNoteAdded(noteUI(from: note))
            summarizeInBackground(note, context: ctx)
            onPill(AmbientPillState(kind: .noted, title: note.title, noteID: note.id))

        case .threadAppend(let existing):
            existing.lastSeenAt = Date()
            existing.seenCount += 1
            store.update(existing)
            onNoteUpdated(noteUI(from: existing))
            summarizeInBackground(existing, context: ctx, force: true)
            pendingDuplicate = (ctx, candidate)
            onPill(AmbientPillState(kind: .duplicate, title: existing.title, noteID: existing.id))

        case .unique:
            let note = makeNote(from: ctx, candidate: candidate)
            store.add(note)
            onNoteAdded(noteUI(from: note))
#if os(macOS)
            postNativeNotification(title: "Noted", body: String(note.title.prefix(80)))
#endif
            summarizeInBackground(note, context: ctx)
            onPill(AmbientPillState(kind: .noted, title: note.title, noteID: note.id))
        }
    }

    private func makeNote(from ctx: CaptureContext, candidate: DedupeEngine.Candidate) -> Note {
        let note = Note(
            canonicalURL: candidate.canonicalURL,
            source: ctx.source,
            domain: ctx.domain,
            author: ctx.author,
            title: ctx.sourceInfo.map(SourceDetector.title(for:)) ?? String(ctx.title.prefix(60)),
            capturedAt: ctx.capturedAt,
            contentHash: candidate.contentHash,
            simhash: candidate.simhash,
            embedding: candidate.embedding,
            threadID: ctx.threadID
        )
        note.sourceText = String(ctx.text.prefix(4000))
        return note
    }

    /// Re-runs the summarizer over the text captured for `id`.
    func regenerate(noteID id: UUID) {
        guard let note = store.allNotes().first(where: { $0.id == id }), let text = note.sourceText else { return }
        let ctx = CaptureContext(
            rawURL: note.canonicalURL.isEmpty ? nil : note.canonicalURL, title: note.title, text: text,
            author: note.author, domain: note.domain, source: note.source,
            sourceInfo: SourceInfo(source: note.source, author: note.author, site: note.domain, subject: note.title,
                                   kind: note.source.displayName)
        )
        note.state = .summarizing
        onNoteUpdated(NoteUI(note))
        summarizeInBackground(note, context: ctx, force: true)
    }

    private func summarizeInBackground(_ note: Note, context: CaptureContext, force: Bool = false) {
        let directive = directiveProvider()
        Task { [weak self] in
            guard let self else { return }
            _ = force
            do {
                let result = try await self.summarizer.summarize(context, directive: directive)
                note.gist = result.gist
                note.summary = result.summary
                note.keyPoints = result.keyPoints
                note.whyItMatters = result.whyItMatters
                note.tags = result.tags
                note.state = .ready
                store.update(note)
                onNoteUpdated(noteUI(from: note))
            } catch {
                note.state = .ready
                if note.summary == nil { note.summary = context.text.prefix(200).description }
                if note.gist == nil { note.gist = context.sourceInfo?.subject }
                store.update(note)
                onNoteUpdated(noteUI(from: note))
            }
        }
    }
}

    private func noteUI(from note: Note) -> NoteUI { NoteUI(note) }

#if os(macOS)
    private func postNativeNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { _ in }
    }
    #endif

extension Notification.Name {
    static let ambientPill = Notification.Name("ambientPill")
}
