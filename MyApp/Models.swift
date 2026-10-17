import Foundation
import SwiftData
import CryptoKit

// MARK: - Source

enum Source: String, Codable, CaseIterable, Identifiable {
    case x = "x"
    case linkedin = "linkedin"
    case article = "article"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .x: return "X"
        case .linkedin: return "LinkedIn"
        case .article: return "Article"
        }
    }

    var shortName: String { displayName }
}

// MARK: - Note state

enum NoteState: String, Codable {
    case summarizing
    case ready
}

// MARK: - Note

@Model
final class Note {
    var id: UUID
    var canonicalURL: String
    var sourceRaw: String
    var domain: String
    var author: String?
    var title: String
    var summary: String?
    var keyPoints: [String]
    var whyItMatters: String?
    var tags: [String]
    var capturedAt: Date
    var lastSeenAt: Date
    var seenCount: Int
    var contentHash: String
    var simhash: UInt64
    var embedding: [Double]?
    var relatedNoteIDs: [UUID]
    var threadID: String?
    var stateRaw: String

    init(canonicalURL: String,
         source: Source,
         domain: String,
         author: String? = nil,
         title: String,
         capturedAt: Date = Date(),
         contentHash: String = "",
         simhash: UInt64 = 0,
         embedding: [Double]? = nil,
         threadID: String? = nil) {
        self.id = UUID()
        self.canonicalURL = canonicalURL
        self.sourceRaw = source.rawValue
        self.domain = domain
        self.author = author
        self.title = title
        self.summary = nil
        self.keyPoints = []
        self.whyItMatters = nil
        self.tags = []
        self.capturedAt = capturedAt
        self.lastSeenAt = capturedAt
        self.seenCount = 1
        self.contentHash = contentHash
        self.simhash = simhash
        self.embedding = embedding
        self.relatedNoteIDs = []
        self.threadID = threadID
        self.stateRaw = NoteState.summarizing.rawValue
    }

    var source: Source {
        get { Source(rawValue: sourceRaw) ?? .article }
        set { sourceRaw = newValue.rawValue }
    }

    var state: NoteState {
        get { NoteState(rawValue: stateRaw) ?? .summarizing }
        set { stateRaw = newValue.rawValue }
    }

    static func todayRange(now: Date = Date()) -> (start: Date, end: Date) {
        let cal = Calendar.current
        let start = cal.startOfDay(for: now)
        let end = cal.date(byAdding: .day, value: 1, to: start) ?? now
        return (start, end)
    }

    var isToday: Bool {
        let (s, e) = Self.todayRange()
        return capturedAt >= s && capturedAt < e
    }
}

// MARK: - Capture context

struct CaptureContext {
    let rawURL: String?
    let title: String
    let text: String
    let author: String?
    let domain: String
    let source: Source
    let appBundleID: String?
    let isPrivate: Bool
    let capturedAt: Date
    let threadID: String?
    let wordCount: Int

    init(rawURL: String? = nil,
         title: String,
         text: String,
         author: String? = nil,
         domain: String,
         source: Source,
         appBundleID: String? = nil,
         isPrivate: Bool = false,
         capturedAt: Date = Date(),
         threadID: String? = nil,
         wordCount: Int? = nil) {
        self.rawURL = rawURL
        self.title = title
        self.text = text
        self.author = author
        self.domain = domain
        self.source = source
        self.appBundleID = appBundleID
        self.isPrivate = isPrivate
        self.capturedAt = capturedAt
        self.threadID = threadID
        self.wordCount = wordCount ?? text.split(whereSeparator: { $0.isWhitespace }).count
    }
}

// MARK: - Summary result

struct SummaryResult {
    let title: String
    let summary: String
    let keyPoints: [String]
    let whyItMatters: String
    let tags: [String]
}

// MARK: - URL canonicalization helper (used by DedupeEngine)

enum URLCanonicalizer {
    static let trackingParams: Set<String> = [
        "utm_source","utm_medium","utm_campaign","utm_term","utm_content",
        "fbclid","gclid","ref","share","s","si","igshid","mc_cid","mc_eid"
    ]

    static func canonicalize(_ raw: String?) -> String {
        guard let raw, let url = URL(string: raw) else { return "" }
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        // Host normalization
        if let host = components?.host?.lowercased() {
            var h = host
            // Drop mobile/amp prefixes
            for prefix in ["m.", "mobile.", "amp.", "www."] {
                if h.hasPrefix(prefix) { h.removeFirst(prefix.count) }
            }
            // Unify x.com / twitter.com
            if h == "twitter.com" || h == "x.com" { h = "x.com" }
            components?.host = h
        }
        // LinkedIn: resolve activity/post IDs into a stable path
        if let host = components?.host, host.contains("linkedin.com") {
            // Keep the path but strip query; activity id preserved
        }
        // Strip tracking params
        if let items = components?.queryItems {
            let filtered = items.filter { item in
                !trackingParams.contains(item.name.lowercased()) && !item.name.lowercased().hasPrefix("utm_")
            }
            components?.queryItems = filtered.isEmpty ? nil : filtered
        }
        // Remove fragment
        components?.fragment = nil
        // Remove trailing slash
        if var path = components?.path, path.count > 1 && path.hasSuffix("/") {
            path.removeLast()
            components?.path = path
        }
        return components?.string ?? raw.lowercased()
    }
}

// MARK: - Text normalization / hashing

enum TextNormalizer {
    static func normalize(_ text: String) -> String {
        text.lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    static func removeBoilerplate(_ text: String) -> String {
        // Minimal boilerplate removal: collapse repeats; keep for hashing.
        normalize(text)
    }

    static func sha256(_ text: String) -> String {
        let data = Data(removeBoilerplate(text).utf8)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - SimHash (64-bit, char trigrams)

enum SimHasher {
    static func hash(_ text: String) -> UInt64 {
        let normalized = TextNormalizer.normalize(text)
        var vector = [Int](repeating: 0, count: 64)
        let features = shingles(normalized, k: 3)
        for feature in features {
            let h = hash64(feature)
            for i in 0..<64 {
                if (h >> i) & 1 == 1 { vector[i] += 1 } else { vector[i] -= 1 }
            }
        }
        var result: UInt64 = 0
        for i in 0..<64 {
            if vector[i] >= 0 { result |= (1 << i) }
        }
        return result
    }

    static func hammingDistance(_ a: UInt64, _ b: UInt64) -> Int {
        (a ^ b).nonzeroBitCount
    }

    private static func shingles(_ text: String, k: Int) -> [String] {
        let chars = Array(text)
        guard chars.count >= k else { return [text] }
        var out: [String] = []
        var i = 0
        while i + k <= chars.count {
            out.append(String(chars[i..<(i+k)]))
            i += 1
        }
        return out
    }

    private static func hash64(_ s: String) -> UInt64 {
        var hash: UInt64 = 5381
        for c in s.unicodeScalars {
            hash = ((hash << 5) &+ hash) &+ UInt64(c.value)
        }
        return hash
    }
}

// MARK: - Crypto helper used elsewhere

extension String {
    var sha256: String { TextNormalizer.sha256(self) }
}
