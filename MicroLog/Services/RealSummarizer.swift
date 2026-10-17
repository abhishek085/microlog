import Foundation

/// Summarizer backed by a small local instruct model (Qwen3.5-0.8B) via SummarizerEngine.
/// Throws if the model isn't downloaded yet or generation fails; ReadingCaptureService already
/// falls back to a plain text excerpt on failure, so no internal mock fallback is needed here.
///
/// The note *title* is not generated here: it comes from where the capture was made (see
/// SourceDetector), which is more reliable than a 0.8B model and tells you the origin at a glance.
/// The model's job is the `gist` — a one-line "what is this" — plus a short summary.
struct RealSummarizer: Summarizer {
    func summarize(_ context: CaptureContext, directive: String) async throws -> SummaryResult {
        let systemPrompt = """
        You write entries for a personal reading journal from text captured off the reader's screen. \
        The text may include unrelated screen clutter (menus, sidebars, other posts); focus on the \
        main item the reader was looking at. Fields:
        - gist: ONE line, at most 90 characters, that lets the reader instantly recall what this was. \
        It must begin with the exact opening phrase you are given, followed by the specific subject \
        with its most useful concrete detail (product/version, role + company + pay, claim, number). \
        Do not repeat the kind of content after the opening phrase (never "Tweet about a tweet"). \
        No quotes, no trailing period. Examples: \
        "Tweet about the new Swift Testing framework replacing XCTest" / \
        "LinkedIn job post: Staff ML Engineer at Acme, remote, $220-260k" / \
        "Article on Postgres vs SQLite for local-first apps".
        - summary: 2-3 plain, factual sentences with the concrete details (names, numbers, versions, \
        company, role, location). Do not pad.
        - keyPoints: 2-4 short bullets.
        - whyItMatters: one sentence tailored to the reader's focus directive.
        - tags: 1-5 lowercase tags of 1-3 words.
        """

        let info = context.sourceInfo
        let userPrompt = """
        Reader's focus directive: \(directive)

        Kind of content: \(info?.kind ?? context.source.displayName)
        Gist must begin with: "\(info?.gistLead ?? "Page about")"
        Where: \(info?.site ?? context.domain)
        Author/Account: \(context.author ?? "unknown")
        Window title: \(context.title)

        Captured text:
        \(context.text.prefix(4000))
        """

        let data = try await SummarizerEngine.shared.generateSummary(systemPrompt: systemPrompt, userPrompt: userPrompt)
        let decoded = try JSONDecoder().decode(GeneratedSummary.self, from: data)

        // Small models drift from the requested opening; enforce it so rows scan consistently.
        var gist = decoded.gist.trimmingCharacters(in: .whitespacesAndNewlines)
        let lead = info?.gistLead ?? "Page about"
        if !gist.lowercased().hasPrefix(lead.lowercased()) {
            gist = lead + " " + (gist.first.map { String($0).lowercased() + gist.dropFirst() } ?? "")
        }

        let fallbackTitle = info.map(SourceDetector.title(for:)) ?? String(context.title.prefix(60))
        return SummaryResult(
            title: fallbackTitle,
            gist: String(gist.prefix(120)),
            summary: decoded.summary,
            keyPoints: decoded.keyPoints,
            whyItMatters: decoded.whyItMatters,
            tags: decoded.tags
        )
    }

    private struct GeneratedSummary: Decodable {
        let gist: String
        let summary: String
        let keyPoints: [String]
        let whyItMatters: String
        let tags: [String]
    }
}
