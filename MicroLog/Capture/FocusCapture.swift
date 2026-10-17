#if os(macOS)
import AppKit
import ApplicationServices
import Vision
import CoreGraphics
import ScreenCaptureKit

enum FocusCapture {
    private static var lastExternalApp: NSRunningApplication?
    private static var observer: NSObjectProtocol?

    /// The app being read. MicroLog activates itself when its popover opens, which would make it
    /// the "frontmost" app, so fall back to the last other app that was active.
    static var targetApp: NSRunningApplication? {
        let front = NSWorkspace.shared.frontmostApplication
        if let front, front.processIdentifier != ProcessInfo.processInfo.processIdentifier { return front }
        return lastExternalApp
    }

    static func startTrackingFrontmostApp() {
        guard observer == nil else { return }
        let me = ProcessInfo.processInfo.processIdentifier
        if let front = NSWorkspace.shared.frontmostApplication, front.processIdentifier != me { lastExternalApp = front }
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { note in
            if let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
               app.processIdentifier != me {
                lastExternalApp = app
            }
        }
    }

    struct Capture {
        var text: String
        var imageJPEG: Data?
    }

    static func captureContext() async -> Capture {
        var parts: [String] = []
        if let app = targetApp?.localizedName {
            parts.append("App: \(app)")
        }
        if let title = focusedWindowTitle(), !title.isEmpty {
            parts.append("Window: \(title)")
        }
        if let selection = selectedText(), !selection.isEmpty {
            parts.append("Selection: \(selection)")
        }
        // App + window title alone are only a handful of words; fall back to OCR unless a long
        // selection already gives us enough text to be worth noting (see ReadingCaptureService's 150-word floor).
        let wordCount = parts.joined(separator: " ").split(whereSeparator: \.isWhitespace).count
        // One screenshot feeds both paths: OCR text for the (text-only) summarizer and word count,
        // and the image itself for EmbeddingGemma 2's vision encoder.
        var jpeg: Data?
        if let image = await screenshot() {
            jpeg = jpegData(from: image, maxWidth: 1024)
            if wordCount < 150, let ocr = await recognizeText(in: image), !ocr.isEmpty {
                parts.append("Screen: \(ocr)")
            }
        }
        return Capture(text: parts.joined(separator: "\n"), imageJPEG: jpeg)
    }

    static func focusedWindowTitle() -> String? {
        guard let app = targetApp else { return nil }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var windowRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &windowRef) == .success,
              let windowRef else { return nil }
        var titleRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(windowRef as! AXUIElement, kAXTitleAttribute as CFString, &titleRef) == .success else { return nil }
        return titleRef as? String
    }

    /// URL of the page in the focused browser window. Safari exposes AXDocument on the window; Chromium
    /// browsers (and Safari as a fallback) expose AXURL on the AXWebArea somewhere below it, so do a
    /// small bounded search. Returns nil for non-browser apps or when the browser doesn't expose it.
    static func focusedDocumentURL() -> String? {
        guard let app = targetApp else { return nil }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var windowRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &windowRef) == .success,
              let windowRef else { return nil }
        let window = windowRef as! AXUIElement
        var docRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(window, kAXDocumentAttribute as CFString, &docRef) == .success,
           let doc = docRef as? String, doc.hasPrefix("http") { return doc }
        var budget = 120   // elements visited; keeps a pathological AX tree from stalling a poll
        return findWebAreaURL(in: window, depth: 0, budget: &budget)
    }

    private static func findWebAreaURL(in element: AXUIElement, depth: Int, budget: inout Int) -> String? {
        guard depth < 8, budget > 0 else { return nil }
        budget -= 1
        var roleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef)
        if (roleRef as? String) == "AXWebArea" {
            var urlRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXURLAttribute as CFString, &urlRef) == .success {
                if let url = urlRef as? URL { return url.absoluteString }
                if let str = urlRef as? String { return str }
            }
            return nil
        }
        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement] else { return nil }
        for child in children {
            if let found = findWebAreaURL(in: child, depth: depth + 1, budget: &budget) { return found }
        }
        return nil
    }

    static func selectedText() -> String? {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
              let focusedRef else { return nil }
        var selectedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(focusedRef as! AXUIElement, kAXSelectedTextAttribute as CFString, &selectedRef) == .success else { return nil }
        return selectedRef as? String
    }

    private static func screenshot() async -> CGImage? {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
            guard let display = content.displays.first else { return nil }
            let filter = SCContentFilter(display: display, excludingWindows: [])
            let config = SCStreamConfiguration()
            config.width = Int(display.width)
            config.height = Int(display.height)
            return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        } catch {
            return nil
        }
    }

    private static func recognizeText(in cgImage: CGImage) async -> String? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .fast
                let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                do {
                    try handler.perform([request])
                    let text = request.results?
                        .compactMap { $0.topCandidates(1).first?.string }
                        .joined(separator: " ")
                    continuation.resume(returning: (text?.isEmpty == false) ? text : nil)
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    /// Downscales to `maxWidth` and JPEG-encodes; keeps the request to the embedding server small.
    private static func jpegData(from image: CGImage, maxWidth: Int) -> Data? {
        let scale = min(1.0, Double(maxWidth) / Double(image.width))
        let w = max(1, Int(Double(image.width) * scale)), h = max(1, Int(Double(image.height) * scale))
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        ctx.interpolationQuality = .medium
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let scaled = ctx.makeImage() else { return nil }
        return NSBitmapImageRep(cgImage: scaled).representation(using: .jpeg, properties: [.compressionFactor: 0.7])
    }
}
#else
enum FocusCapture {
    struct Capture { var text: String; var imageJPEG: Data? }
    static func captureContext() async -> Capture { Capture(text: "", imageJPEG: nil) }
}
#endif
