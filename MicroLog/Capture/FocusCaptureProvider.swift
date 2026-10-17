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
    private var lastCaptured: (key: String, at: Date)?
    /// A window we've already captured isn't re-screenshotted/OCR'd on every poll while it stays focused.
    private let recaptureInterval: TimeInterval = 300

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
        guard let app = FocusCapture.targetApp else { return nil }
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

        if let last = lastCaptured, last.key == key, now.timeIntervalSince(last.at) < recaptureInterval {
            return nil
        }

        let capture = await FocusCapture.captureContext()
        let raw = capture.text
        guard !raw.isEmpty else { return nil }

        lastCaptured = (key, now)
        let url = FocusCapture.focusedDocumentURL()
        let info = SourceDetector.detect(appName: appName, windowTitle: windowTitle, url: url)
        let isPrivate = windowTitle.localizedCaseInsensitiveContains("private")

        return CaptureContext(
            rawURL: url,
            title: windowTitle.isEmpty ? appName : windowTitle,
            text: raw,
            author: info.author,
            domain: info.site,
            source: info.source,
            appBundleID: bundleID,
            isPrivate: isPrivate,
            imageData: capture.imageJPEG,
            sourceInfo: info
        )
    }
}
#endif
