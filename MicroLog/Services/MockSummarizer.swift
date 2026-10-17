import Foundation

final class MockSummarizer: Summarizer {
    func summarize(_ context: CaptureContext, directive: String) async throws -> SummaryResult {
        // Simulate latency
        try? await Task.sleep(for: .milliseconds(300))
        return SummaryResult(
            title: String(context.title.prefix(60)),
            gist: "Page about \(context.title.prefix(60))",
            summary: "A concise 3-4 sentence summary of the captured page tailored to the reader's directive. (context.text.prefix(80))",
            keyPoints: [
                "Key point one from the page",
                "Key point two relevant to the directive",
                "Key point three worth remembering"
            ],
            whyItMatters: "Directly relevant to your directive and helps you track developments in local AI.",
            tags: ["local-ai", "llm", context.source.displayName.lowercased()]
        )
    }
}
