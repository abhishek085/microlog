import SwiftUI

struct NoteUI: Identifiable, Equatable {
    let id: UUID
    var title: String
    var gist: String
    var url: String
    var source: Source
    var domain: String
    var author: String?
    var capturedAt: Date
    var seenCount: Int
    var isSummarizing: Bool
    var summary: String
    var keyPoints: [String]
    var whyItMatters: String
    var tags: [String]

    init(id: UUID = UUID(), title: String, gist: String = "", url: String = "", source: Source, domain: String, author: String? = nil, capturedAt: Date = Date(), seenCount: Int = 1, isSummarizing: Bool = false, summary: String = "", keyPoints: [String] = [], whyItMatters: String = "", tags: [String] = []) {
        self.id = id
        self.title = title
        self.gist = gist
        self.url = url
        self.source = source
        self.domain = domain
        self.author = author
        self.capturedAt = capturedAt
        self.seenCount = seenCount
        self.isSummarizing = isSummarizing
        self.summary = summary
        self.keyPoints = keyPoints
        self.whyItMatters = whyItMatters
        self.tags = tags
    }

    init(_ note: Note) {
        self.init(
            id: note.id, title: note.title, gist: note.gist ?? "", url: note.canonicalURL, source: note.source,
            domain: note.domain, author: note.author, capturedAt: note.capturedAt, seenCount: note.seenCount,
            isSummarizing: note.state == .summarizing, summary: note.summary ?? "", keyPoints: note.keyPoints,
            whyItMatters: note.whyItMatters ?? "", tags: note.tags
        )
    }

    static func samples(count: Int = 6) -> [NoteUI] {
        let titles = [
            "On-device LLMs arrive on macOS", "Thread about agents running locally", "Building a local AI stack",
            "Quantized models for embeddings", "Prompt caching and context windows", "Privacy-first summarization",
            "SwiftUI concurrency tips", "Core ML model conversion", "ScreenCaptureKit basics", "Accessibility-driven capture",
            "SimHash duplicate detection", "Embedding cosine similarity", "NSPopover native behavior", "SwiftData migrations",
            "macOS material backgrounds", "Spring animations in SwiftUI", "SF Symbols best practices", "AppKit status items",
            "Automation permissions flow", "Reading time thresholds"
        ]
        let sources: [Source] = [.x, .linkedin, .article]
        let domains = ["x.com", "linkedin.com", "example.com"]
        return (0..<count).map { i in
            NoteUI(
                title: titles[i % titles.count],
                source: sources[i % sources.count],
                domain: domains[i % domains.count],
                author: i % 2 == 0 ? "Jane" : "@mike",
                capturedAt: Date().addingTimeInterval(-Double(i * 60 * 7)),
                seenCount: i == 2 ? 3 : 1,
                isSummarizing: i == 1,
                summary: "A short 3-4 sentence summary of the captured page. It explains the core idea, why it is interesting, and what to take away for future reading.",
                keyPoints: ["First key point", "Second key point", "Third key point"],
                whyItMatters: "Directly relevant to your directive and helps you track new developments.",
                tags: ["local-ai", "llm"]
            )
        }
    }
}

@Observable
final class ReadingNotesUIState {
    var persona: String = "Research Digest"
    var directive: String = "Prioritise LLMs, agents and local AI. Skip engagement bait and hot takes. Keep summaries factual."
    var isEditingDirective: Bool = false
    var draftDirective: String = ""
    var isPaused: Bool = false
    var visibleCount: Int = 15
    var selectedNoteID: UUID? = nil
    var showSettings: Bool = false
    var ambient: AmbientPillState? = nil
    var setupStatus: String? = nil
    var searchText: String = ""
    var notes: [NoteUI] = NoteUI.samples(count: 6)

    // empty hooks
    var onOpenURL: (NoteUI) -> Void = { _ in }
    var onCopy: (NoteUI) -> Void = { _ in }
    var onDelete: (NoteUI) -> Void = { _ in }
    var onRegenerate: (NoteUI) -> Void = { _ in }
    var onPauseToggle: () -> Void = { }
    var onOpenSettings: () -> Void = { }
    var onTakeNote: () -> Void = { }
    var onQuit: () -> Void = { }
    var onSaveAsNew: () -> Void = { }

    func takeNote() {
        // Delegate to the injected capture pipeline (if available).
        onTakeNote()
    }

    /// Notes matching the search box (title, gist, summary, author, site, tags).
    var filteredNotes: [NoteUI] {
        let q = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return notes }
        return notes.filter { n in
            [n.title, n.gist, n.summary, n.author ?? "", n.domain, n.tags.joined(separator: " ")]
                .contains { $0.lowercased().contains(q) }
        }
    }

    var displayedNotes: [NoteUI] { Array(filteredNotes.prefix(visibleCount)) }

    /// Today's notes as Markdown, ready to paste into a journal, standup or newsletter draft.
    func todayDigestMarkdown() -> String {
        let cal = Calendar.current
        let today = notes.filter { cal.isDateInToday($0.capturedAt) }.sorted { $0.capturedAt < $1.capturedAt }
        let f = DateFormatter(); f.dateFormat = "EEE, MMM d"
        let t = DateFormatter(); t.dateFormat = "HH:mm"
        var out = "# Reading log — \(f.string(from: Date()))\n\n"
        for n in today {
            let link = n.url.isEmpty ? n.title : "[\(n.title)](\(n.url))"
            out += "- \(t.string(from: n.capturedAt)) \(link)"
            if !n.gist.isEmpty { out += " — \(n.gist)" }
            out += "\n"
            if !n.summary.isEmpty { out += "  - \(n.summary)\n" }
        }
        return out
    }
}

enum AmbientPillKind { case noted, duplicate, askToSave }

struct AmbientPillState: Identifiable, Equatable {
    let id: UUID = UUID()
    let kind: AmbientPillKind
    let title: String
    let noteID: UUID
}
