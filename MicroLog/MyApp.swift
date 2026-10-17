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

    private var signalSources: [DispatchSourceSignal] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        // A previous instance that was force-quit or crashed leaves llama-server orphaned,
        // still holding its port and model memory.
        ServerProcessRegistry.shared.killStaleServers()
        FocusCapture.startTrackingFrontmostApp()
        installSignalHandlers()
        offerMoveToApplications()
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
            // Template image cut from the app logo so it tints correctly in light/dark menu bars.
            let icon = NSImage(named: "MenuBarIcon") ?? NSImage(systemSymbolName: "sparkles", accessibilityDescription: nil)
            icon?.isTemplate = true
            icon?.accessibilityDescription = "MicroLog"
            button.image = icon
            button.action = #selector(togglePopover(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.target = self
        }

        // Real capture service enabled.
        let _ = container
        uiState.onTakeNote = { [weak self] in
            guard let self, let svc = self.captureService else { return }
            Task { await svc.captureOne() }
        }
        uiState.onRegenerate = { [weak self] note in self?.captureService?.regenerate(noteID: note.id) }
        uiState.onQuit = { NSApp.terminate(nil) }
        uiState.onSaveAsNew = { [weak self] in
            self?.captureService?.saveAsNewFromPending()
        }
        let store = SwiftDataNoteStore(context: container.mainContext)
        uiState.onPauseToggle = { [weak self] in
            guard let self else { return }
            // Called before the UI flips isPaused, so the current value is the pre-toggle state.
            if self.uiState.isPaused { self.captureService?.start() } else { self.captureService?.stop() }
        }
        uiState.onDelete = { note in
            if let model = store.allNotes().first(where: { $0.id == note.id }) { store.delete(model) }
        }
        // Hydrate the UI with any notes already persisted in SwiftData.
        uiState.notes = store.allNotes().map(NoteUI.init)
        uiState.onOpenURL = { note in
            if let url = URL(string: note.url), !note.url.isEmpty { NSWorkspace.shared.open(url) }
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

        // First run: fetch the runtime + models, then start capturing and load the embedding
        // model in the background so the first capture doesn't pay the startup cost.
        Task { [weak self] in
            await ModelManager.shared.ensureCoreAssets { msg in
                Task { @MainActor in self?.uiState.setupStatus = msg }
            }
            await EmbeddingEngine.shared.warmUp()
            await service.start()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        captureService?.stop()
        ServerProcessRegistry.shared.terminateAll()
    }

    /// SIGTERM/SIGINT/SIGHUP (e.g. `kill`, logout, Activity Monitor "Quit") don't post
    /// willTerminate by themselves, which is how llama-server used to get orphaned.
    private func installSignalHandlers() {
        for sig in [SIGTERM, SIGINT, SIGHUP] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler { NSApp.terminate(nil) }
            source.resume()
            signalSources.append(source)
        }
    }

    /// The app is menu-bar only (no Dock icon), so if it isn't in /Applications there's no
    /// Launchpad/Finder entry to find or uninstall it from. Offer to put it there.
    private func offerMoveToApplications() {
        let bundleURL = Bundle.main.bundleURL
        let appsDir = URL(fileURLWithPath: "/Applications", isDirectory: true)
        let userAppsDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")
        guard !bundleURL.path.hasPrefix(appsDir.path), !bundleURL.path.hasPrefix(userAppsDir.path),
              !bundleURL.path.contains("/DerivedData/"), !bundleURL.path.contains("/scratchpad/"),
              UserDefaults.standard.bool(forKey: "declinedMoveToApplications") == false else { return }
        let alert = NSAlert()
        alert.messageText = "Move MicroLog to Applications?"
        alert.informativeText = "MicroLog lives in the menu bar and has no Dock icon. Moving it to Applications makes it easy to find, launch at login and uninstall."
        alert.addButton(withTitle: "Move to Applications")
        alert.addButton(withTitle: "Not Now")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else {
            UserDefaults.standard.set(true, forKey: "declinedMoveToApplications")
            return
        }
        let destination = appsDir.appendingPathComponent(bundleURL.lastPathComponent)
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.trashItem(at: destination, resultingItemURL: nil)
            }
            try FileManager.default.copyItem(at: bundleURL, to: destination)
            let config = NSWorkspace.OpenConfiguration()
            config.createsNewApplicationInstance = true
            NSWorkspace.shared.openApplication(at: destination, configuration: config) { _, _ in
                DispatchQueue.main.async { NSApp.terminate(nil) }
            }
        } catch {
            let failed = NSAlert(error: error)
            failed.runModal()
        }
    }

    private func showStatusMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "Open MicroLog", action: #selector(togglePopover(_:)), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit MicroLog", action: #selector(quit), keyEquivalent: "q").target = self
        // Assigning a menu makes the status item show it for this click only; clear it so left-click
        // keeps toggling the popover.
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc func quit() { NSApp.terminate(nil) }

    @objc func togglePopover(_ sender: Any?) {
        if NSApp.currentEvent?.type == .rightMouseUp, sender as? NSStatusBarButton != nil {
            showStatusMenu()
            return
        }
        if popover.isShown {
            popover.performClose(nil)
        } else if let button = statusItem.button {
            // Accessory (LSUIElement) apps aren't active by default; without this the popover
            // never becomes key, so text fields and the sheet misbehave and it dismisses oddly.
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}
#endif
