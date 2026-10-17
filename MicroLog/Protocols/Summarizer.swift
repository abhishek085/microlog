import Foundation

protocol Summarizer {
    func summarize(_ context: CaptureContext, directive: String) async throws -> SummaryResult
}
