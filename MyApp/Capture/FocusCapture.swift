#if os(macOS)
import AppKit
import ApplicationServices
import Vision
import CoreGraphics
import ScreenCaptureKit

enum FocusCapture {
    static func captureContext() async -> String {
        var parts: [String] = []
        if let app = NSWorkspace.shared.frontmostApplication?.localizedName {
            parts.append("App: \(app)")
        }
        if let title = focusedWindowTitle(), !title.isEmpty {
            parts.append("Window: \(title)")
        }
        if let selection = selectedText(), !selection.isEmpty {
            parts.append("Selection: \(selection)")
        }
        if parts.count < 2, let ocr = await screenOCR(), !ocr.isEmpty {
            parts.append("Screen: \(ocr)")
        }
        return parts.joined(separator: "\n")
    }

    static func focusedWindowTitle() -> String? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var windowRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &windowRef) == .success,
              let windowRef else { return nil }
        var titleRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(windowRef as! AXUIElement, kAXTitleAttribute as CFString, &titleRef) == .success else { return nil }
        return titleRef as? String
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

    static func screenOCR() async -> String? {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
            guard let display = content.displays.first else { return nil }
            let filter = SCContentFilter(display: display, excludingWindows: [])
            let config = SCStreamConfiguration()
            config.width = Int(display.width)
            config.height = Int(display.height)
            let cgImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            return await withCheckedContinuation { continuation in
                let request = VNRecognizeTextRequest { req, _ in
                    let text = (req.results as? [VNRecognizedTextObservation])?
                        .compactMap { $0.topCandidates(1).first?.string }
                        .joined(separator: " ")
                    continuation.resume(returning: (text?.isEmpty == false) ? text : nil)
                }
                request.recognitionLevel = .fast
                let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                try? handler.perform([request])
            }
        } catch {
            return nil
        }
    }
}
#else
enum FocusCapture {
    static func captureContext() async -> String { "" }
}
#endif
