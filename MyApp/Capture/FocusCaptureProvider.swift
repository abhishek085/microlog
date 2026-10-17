import Foundation
#if os(macOS)
import AppKit

/// Real on-device capture provider backed by Accessibility + ScreenCaptureKit/Vision OCR (see FocusCapture).
/// Tracks dwell time on the current focused app/window and only returns content once the user has been
/// looking at the same window for at least `policy.minimumReadTime`, to avoid noise from rapid app switching.
final class FocusCaptureProvider: CaptureProvider {
    private let policy: CapturePolicy
    private var dwellKey: String?
    private var dwellStart: Date?

    init(policy: CapturePolicy = CapturePolicy(
        allowedDomains: [],
        deniedApps: [
            "com.apple.mail", "com.apple.MobileSMS", "com.apple.Terminal",
            "com.apple.systempreferences", "com.1password.1password",
            "com.agilebits.onepassword7", "com.apple.keychainaccess"
        ]
    )) {
        self.policy = policy
    }

    func currentContext() async throws -> CaptureContext? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let appName = app.localizedName ?? "Unknown"
        let bundleID = app.bundleIdentifier ?? ""

        // `domain` here is repurposed as the frontmost app's display name, since this provider
        // has no browser URL to inspect (unlike the Scripting Bridge path described in the README).
        guard policy.isAllowed(domain: appName, app: bundleID) else {
            dwellKey = nil
            return nil
        }

        let windowTitle = FocusCapture.focusedWindowTitle() ?? ""
        let key = "\(bundleID)|\(windowTitle)"

        let now = Date()
        if dwellKey != key {
            // Focus just changed to a new window; start the dwell clock instead of capturing immediately.
            dwellKey = key
            dwellStart = now
            return nil
        }
        guard let start = dwellStart, now.timeIntervalSince(start) >= policy.minimumReadTime else {
            return nil
        }

        let raw = await FocusCapture.captureContext()
        guard !raw.isEmpty else { return nil }

        let isPrivate = windowTitle.localizedCaseInsensitiveContains("private")
        let title = windowTitle.isEmpty ? appName : windowTitle

        return CaptureContext(
            title: title,
            text: raw,
            domain: appName,
            source: .article,
            appBundleID: bundleID,
            isPrivate: isPrivate
        )
    }
}
#endif
