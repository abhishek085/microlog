import Foundation

final class MockCaptureProvider: CaptureProvider {
    private var tick = 0

    func currentContext() async throws -> CaptureContext? {
        tick += 1
        let idx = tick % 2
        let baseText = idx == 0
            ? "A thread about running local LLMs on a Mac. Embeddings, quantization, and on-device inference. No cloud calls. Privacy first."
            : "A local AI stack combines Core ML models, SwiftData, and AppKit to deliver fast, private summarization."
        // Make each capture unique so the pipeline visibly creates rows while also demonstrating dedupe on repeats.
        let uniqueText = "\(baseText) Variation \(tick). " + String(repeating: "Additional readable content to satisfy the minimum word count threshold. ", count: 22)
        return CaptureContext(
            rawURL: idx == 0 ? "https://x.com/jack/status/\(1000 + tick)" : "https://example.com/article/\(tick)",
            title: idx == 0 ? "Jack on X: local LLMs variation \(tick)" : "Building a local AI stack variant \(tick)",
            text: uniqueText,
            author: idx == 0 ? "@jack" : "Jane",
            domain: idx == 0 ? "x.com" : "example.com",
            source: idx == 0 ? .x : .article,
            appBundleID: "com.apple.Safari",
            isPrivate: false,
            threadID: idx == 0 ? nil : nil
        )
    }
}
