import Foundation

/// Summarizer backed by a small local instruct model (Qwen3.5-0.8B) via SummarizerEngine.
/// Throws if the model isn't downloaded yet or generation fails; ReadingCaptureService already
/// falls back to a plain text excerpt on failure, so no internal mock fallback is needed here.
struct RealSummarizer: Summarizer {
    func summarize(_ context: CaptureContext, directive: String) async throws -> SummaryResult {
        let systemPrompt = """
        You summarize a single piece of captured reading content for a personal reading journal. \
        The reader has stated a focus directive describing what they care about. Write the summary \
        and "why it matters" tailored to that directive. Keep the summary factual, 3-4 sentences. \
        Keep key points short. Tags should be 1-3 words, lowercase.
        """

        let userPrompt = """
        Reader's focus directive: \(directive)

        Source: \(context.source.displayName)
        Domain: \(context.domain)
        Title: \(context.title)
        Author: \(context.author ?? "unknown")

        Captured content:
        \(context.text.prefix(4000))
        """

        let data = try await SummarizerEngine.shared.generateSummary(systemPrompt: systemPrompt, userPrompt: userPrompt)
        let decoded = try JSONDecoder().decode(GeneratedSummary.self, from: data)

        return SummaryResult(
            title: decoded.title.isEmpty ? String(context.title.prefix(60)) : String(decoded.title.prefix(60)),
            summary: decoded.summary,
            keyPoints: decoded.keyPoints,
            whyItMatters: decoded.whyItMatters,
            tags: decoded.tags
        )
    }

    private struct GeneratedSummary: Decodable {
        let title: String
        let summary: String
        let keyPoints: [String]
        let whyItMatters: String
        let tags: [String]
    }
}
