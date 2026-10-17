import XCTest
@testable import MicroLog

final class DedupeEngineTests: XCTestCase {
    var engine: DedupeEngine!

    override func setUp() {
        super.setUp()
        engine = DedupeEngine()
    }

    func makeNote(url: String, text: String, threadID: String? = nil) async -> Note {
        let candidate = await DedupeEngine.makeCandidate(from: CaptureContext(
            rawURL: url, title: "Title", text: text, domain: "example.com", source: .article, threadID: threadID
        ))
        let note = Note(
            canonicalURL: candidate.canonicalURL,
            source: .article,
            domain: "example.com",
            title: "Title",
            contentHash: candidate.contentHash,
            simhash: candidate.simhash,
            embedding: candidate.embedding,
            threadID: threadID
        )
        return note
    }

    // 1. Same URL with tracking params -> duplicate
    func testSameURLWithTrackingParams() async {
        let text = "An article about on-device LLMs and embeddings for privacy-first summarization."
        let a = await makeNote(url: "https://example.com/post?utm_source=twitter&fbclid=abc", text: text)
        let candidate = await DedupeEngine.makeCandidate(from: CaptureContext(rawURL: "https://example.com/post?utm_source=newsletter", title: "T", text: text, domain: "example.com", source: .article))
        let decision = engine.evaluate(candidate: candidate, against: [a])
        switch decision {
        case .duplicate: break
        default: XCTFail("Expected duplicate for same URL with tracking params")
        }
    }

    // 2. x.com vs twitter.com -> duplicate
    func testXvsTwitter() async {
        let text = "A post about agents running locally without cloud calls."
        let a = await makeNote(url: "https://twitter.com/user/status/1", text: text)
        let candidate = await DedupeEngine.makeCandidate(from: CaptureContext(rawURL: "https://x.com/user/status/1", title: "T", text: text, domain: "x.com", source: .x))
        let decision = engine.evaluate(candidate: candidate, against: [a])
        switch decision {
        case .duplicate: break
        default: XCTFail("Expected duplicate for x.com vs twitter.com")
        }
    }

    // 3. Same article, different URL -> duplicate
    func testSameArticleDifferentURL() async {
        let text = "Identical article body repeated here for hashing purposes. Local models and summarization."
        let a = await makeNote(url: "https://site-a.com/article", text: text)
        let candidate = await DedupeEngine.makeCandidate(from: CaptureContext(rawURL: "https://site-b.com/mirror", title: "T", text: text, domain: "site-b.com", source: .article))
        let decision = engine.evaluate(candidate: candidate, against: [a])
        switch decision {
        case .duplicate: break
        default: XCTFail("Expected duplicate for identical content")
        }
    }

    // 4. Lightly edited repost -> duplicate
    func testLightlyEditedRepost() async {
        let a = await makeNote(url: "https://x.com/u/status/2", text: "Running local LLMs on a Mac with embeddings and quantization. Privacy first, no cloud.")
        let edited = "Running local LLMs on a Mac with embeddings and quantization. Privacy first, no cloud calls at all."
        let candidate = await DedupeEngine.makeCandidate(from: CaptureContext(rawURL: "https://x.com/u/status/3", title: "T", text: edited, domain: "x.com", source: .x))
        let decision = engine.evaluate(candidate: candidate, against: [a])
        switch decision {
        case .duplicate, .related: break
        default: XCTFail("Expected duplicate/related for lightly edited repost, got \(decision)")
        }
    }

    // 5. Thread growing over time -> threadAppend
    func testThreadGrowing() async {
        let a = await makeNote(url: "https://x.com/u/status/9", text: "First tweet in the thread.", threadID: "thread-1")
        let candidate = await DedupeEngine.makeCandidate(from: CaptureContext(rawURL: "https://x.com/u/status/10", title: "T", text: "Second tweet in the thread.", domain: "x.com", source: .x, threadID: "thread-1"))
        let decision = engine.evaluate(candidate: candidate, against: [a])
        switch decision {
        case .threadAppend: break
        default: XCTFail("Expected thread append")
        }
    }

    // 6. Two genuinely different articles on same topic -> NOT flagged
    func testDifferentArticlesSameTopic() async {
        let a = await makeNote(url: "https://a.com/post1", text: "A comprehensive guide to training neural networks from scratch with backpropagation.")
        let text2 = "Benchmark results comparing GPU throughput across three cloud providers for inference workloads."
        let candidate = await DedupeEngine.makeCandidate(from: CaptureContext(rawURL: "https://b.com/post2", title: "T", text: text2, domain: "b.com", source: .article))
        let decision = engine.evaluate(candidate: candidate, against: [a])
        switch decision {
        case .unique: break
        default: XCTFail("Expected unique for different articles, got \(decision)")
        }
    }
}
