import Foundation

/// Pure, UI-free duplicate detection engine.
struct DedupeEngine {
    // Thresholds
    var duplicateSimilarity: Double = 0.90
    var relatedThresholdLow: Double = 0.89

    struct Candidate {
        let canonicalURL: String
        let contentHash: String
        let simhash: UInt64
        let embedding: [Double]?
        let threadID: String?
        let capturedAt: Date
    }

    enum Decision {
        case duplicate(existing: Note)
        case related(existing: Note, similarity: Double)
        case threadAppend(existing: Note)
        case unique
    }

    func evaluate(candidate: Candidate, against notes: [Note]) -> Decision {
        // 1. Thread continuation
        if let tid = candidate.threadID, !tid.isEmpty {
            if let existing = notes.first(where: { $0.threadID == tid }) {
                return .threadAppend(existing: existing)
            }
        }

        // 2. Exact canonical URL
        if !candidate.canonicalURL.isEmpty {
            if let existing = notes.first(where: { $0.canonicalURL == candidate.canonicalURL }) {
                return .duplicate(existing: existing)
            }
        }

        // 3. Content hash
        if !candidate.contentHash.isEmpty {
            if let existing = notes.first(where: { $0.contentHash == candidate.contentHash }) {
                return .duplicate(existing: existing)
            }
        }

        // 4. Near-duplicate via embedding cosine + simhash
        var bestSimilarity: Double = 0
        var bestNote: Note?
        for note in notes {
            var similarity = 0.0
            if let a = candidate.embedding, let b = note.embedding, !a.isEmpty, !b.isEmpty {
                similarity = cosineSimilarity(a, b)
            } else {
                // Fall back to simhash proximity converted to 0..1
                let dist = SimHasher.hammingDistance(candidate.simhash, note.simhash)
                similarity = 1.0 - (Double(dist) / 64.0)
            }
            if similarity > bestSimilarity {
                bestSimilarity = similarity
                bestNote = note
            }
        }

        if let best = bestNote {
            if bestSimilarity >= duplicateSimilarity {
                return .duplicate(existing: best)
            } else if bestSimilarity >= relatedThresholdLow {
                return .related(existing: best, similarity: bestSimilarity)
            }
        }

        // SimHash hamming distance alone (catches lightly edited reposts)
        if let best = bestNote {
            let dist = SimHasher.hammingDistance(candidate.simhash, best.simhash)
            if dist <= 3 { return .duplicate(existing: best) }
        }

        return .unique
    }

    func cosineSimilarity(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot = 0.0, na = 0.0, nb = 0.0
        for i in a.indices {
            dot += a[i] * b[i]
            na += a[i] * a[i]
            nb += b[i] * b[i]
        }
        let denom = (na.squareRoot() * nb.squareRoot())
        return denom == 0 ? 0 : dot / denom
    }

    // Convenience: build a candidate from context (async to allow on-device embedding).
    static func makeCandidate(from context: CaptureContext, embeddingService: (any EmbeddingService)? = nil) async -> Candidate {
        let service: any EmbeddingService = embeddingService ?? PlaceholderEmbeddingService()
        let embedding = try? await service.embed(text: context.text)
        return Candidate(
            canonicalURL: URLCanonicalizer.canonicalize(context.rawURL),
            contentHash: TextNormalizer.sha256(context.text),
            simhash: SimHasher.hash(context.text),
            embedding: embedding ?? SimpleEmbedding.embed(context.text),
            threadID: context.threadID,
            capturedAt: context.capturedAt
        )
    }
}

/// Trivial deterministic embedding for mock/test usage (256-d bag of words).
enum SimpleEmbedding {
    static func embed(_ text: String) -> [Double] {
        let dim = 256
        var vec = [Double](repeating: 0, count: dim)
        for word in text.lowercased().split(whereSeparator: { $0.isWhitespace }) {
            let h = word.hashValue
            let idx = abs(h) % dim
            vec[idx] += 1
        }
        let norm = vec.reduce(0) { $0 + $1 * $1 }.squareRoot()
        if norm > 0 { vec = vec.map { $0 / norm } }
        return vec
    }
}
