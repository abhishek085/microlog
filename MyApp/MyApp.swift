import SwiftUI
#if os(macOS)
import AppKit
import SwiftData
import UserNotifications

@main
struct MyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    var body: some Scene {
        Settings { EmptyView() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var popover: NSPopover!
    let container: ModelContainer
    var captureService: ReadingCaptureService?
    let uiState = ReadingNotesUIState()

    override init() {
        do {
            let config = ModelConfiguration(isStoredInMemoryOnly: false)
            self.container = try ModelContainer(for: Note.self, configurations: config)
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        uiState.notes = []
        popover = NSPopover()
        popover.contentSize = NSSize(width: 340, height: 420)
        popover.behavior = .transient
        popover.animates = true
        let rootView = PopoverRoot(state: uiState)
        popover.contentViewController = NSHostingController(rootView: rootView)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "Reading Notes")
            button.action = #selector(togglePopover(_:))
            button.target = self
        }

        // Real capture service enabled.
        let _ = container
        uiState.onTakeNote = { [weak self] in
            guard let self, let svc = self.captureService else { return }
            Task { await svc.captureOne() }
        }
        uiState.onSaveAsNew = { [weak self] in
            self?.captureService?.saveAsNewFromPending()
        }
        let store = SwiftDataNoteStore(context: container.mainContext)
        // Hydrate the UI with any notes already persisted in SwiftData.
        uiState.notes = store.allNotes().map { note in
            NoteUI(
                id: note.id,
                title: note.title,
                source: note.source,
                domain: note.domain,
                author: note.author,
                capturedAt: note.capturedAt,
                seenCount: note.seenCount,
                isSummarizing: note.state == .summarizing,
                summary: note.summary ?? "",
                keyPoints: note.keyPoints,
                whyItMatters: note.whyItMatters ?? "",
                tags: note.tags
            )
        }
        let service = ReadingCaptureService(
            provider: FocusCaptureProvider(),
            embedding: LlamaCppEmbeddingService(),
            summarizer: RealSummarizer(),
            store: store,
            context: container.mainContext,
            directiveProvider: { UserDefaults.standard.string(forKey: "directive") ?? "Prioritise LLMs, agents and local AI. Skip engagement bait and hot takes. Keep summaries factual." },
            onPill: { msg in Task { @MainActor in self.uiState.ambient = msg } },
            onNoteAdded: { note in Task { @MainActor in self.uiState.notes.insert(note, at: 0) } },
            onNoteUpdated: { note in Task { @MainActor in
                if let idx = self.uiState.notes.firstIndex(where: { $0.id == note.id }) {
                    self.uiState.notes[idx] = note
                }
            } }
        )
        self.captureService = service
        Task { await service.start() }
    }

    @objc func togglePopover(_ sender: Any?) {
        if popover.isShown {
            popover.performClose(nil)
        } else if let button = statusItem.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}
#endif
