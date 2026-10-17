import Foundation

/// Works out *where* a capture came from (X, LinkedIn, Reddit, a site, an app...) and *who* wrote it,
/// from the browser URL when available and otherwise the window title. The note title is built from
/// this rather than asked of the small summarizer model, which is both faster and far more reliable.
struct SourceInfo {
    var source: Source
    var author: String?      // "@handle" or a person/company name
    var site: String         // host without www, or the app name when there's no URL
    var subject: String      // page title with the site suffix stripped
    var kind: String         // human hint for the summarizer: "tweet", "LinkedIn job posting", ...

    /// How the one-line gist should open, so every row reads "Tweet about…", "LinkedIn job post: …".
    var gistLead: String {
        switch kind {
        case "tweet": return "Tweet about"
        case "X timeline": return "X timeline:"
        case "LinkedIn job posting": return "LinkedIn job post:"
        case "LinkedIn post": return "LinkedIn post about"
        case "Reddit thread": return "Reddit thread on"
        case "Hacker News discussion": return "HN discussion on"
        case "YouTube video": return "Video on"
        case "web article": return "Article on"
        default: return kind.hasSuffix("repository page") ? "GitHub repo:" : "\(kind):"
        }
    }
}

enum SourceDetector {
    static func detect(appName: String, windowTitle: String, url: String?) -> SourceInfo {
        let parsed = url.flatMap { URL(string: $0) }
        let host = parsed?.host?.lowercased().replacingOccurrences(of: "www.", with: "")
        let pathParts = (parsed?.path ?? "").split(separator: "/").map(String.init)
        let title = windowTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"^\(\d+\)\s*"#, with: "", options: .regularExpression)  // "(3) " unread badge
        let lower = title.lowercased()
        let site = host ?? appName

        func has(_ h: String) -> Bool { host == h || host?.hasSuffix("." + h) == true }

        // X / Twitter
        if has("x.com") || has("twitter.com") || lower.hasSuffix(" / x") || title.contains(" on X:") {
            var author: String?
            if let first = pathParts.first, !["home", "i", "explore", "search", "notifications", "messages"].contains(first),
               pathParts.count >= 2, pathParts[1] == "status" || pathParts[1] == "article" {
                author = "@" + first
            } else if let name = firstMatch(#"^(.+?) on X:"#, in: title) {
                author = name
            } else if let handle = firstMatch(#"\((@[A-Za-z0-9_]+)\)"#, in: title) {
                author = handle
            }
            let isTweet = pathParts.contains("status") || title.contains(" on X:")
            return SourceInfo(source: .x, author: author, site: "x.com",
                              subject: quoted(title) ?? strip(title, suffixes: ["/ X"]), kind: isTweet ? "tweet" : "X timeline")
        }

        // LinkedIn
        if has("linkedin.com") || lower.hasSuffix("| linkedin") || title.contains(" on LinkedIn") {
            let isJob = pathParts.first == "jobs"
            var author = firstMatch(#"^(.+?) on LinkedIn"#, in: title)
            var subject = quoted(title) ?? strip(title, suffixes: ["| LinkedIn", "- LinkedIn"])
            if isJob {
                // "Staff ML Engineer - Acme | LinkedIn"  ->  author = Acme, subject = Staff ML Engineer
                let parts = subject.components(separatedBy: " - ")
                if parts.count >= 2 { subject = parts[0]; author = parts[1] }
            } else if author == nil, pathParts.first == "in", pathParts.count > 1 {
                author = pathParts[1].replacingOccurrences(of: "-", with: " ").capitalized
            }
            return SourceInfo(source: .linkedin, author: author, site: "linkedin.com", subject: subject,
                              kind: isJob ? "LinkedIn job posting" : "LinkedIn post")
        }

        // Reddit
        if has("reddit.com") || lower.contains(" : r/") {
            var sub = firstMatch(#"(r/[A-Za-z0-9_]+)"#, in: parsed?.path.dropFirst(0).description ?? "")
            if sub == nil { sub = firstMatch(#"(r/[A-Za-z0-9_]+)"#, in: title) }
            let subject = title.components(separatedBy: " : r/").first ?? title
            return SourceInfo(source: .reddit, author: sub, site: "reddit.com", subject: subject, kind: "Reddit thread")
        }

        // Hacker News
        if has("news.ycombinator.com") || lower.hasSuffix("| hacker news") {
            return SourceInfo(source: .hackernews, author: nil, site: "news.ycombinator.com",
                              subject: strip(title, suffixes: ["| Hacker News"]), kind: "Hacker News discussion")
        }

        // GitHub
        if has("github.com") || lower.hasSuffix("· github") || lower.hasPrefix("github -") {
            var repo: String?
            if pathParts.count >= 2 { repo = pathParts[0] + "/" + pathParts[1] }
            else { repo = firstMatch(#"^([\w.-]+/[\w.-]+)"#, in: title) }
            let kind = pathParts.contains("issues") ? "GitHub issue" : pathParts.contains("pull") ? "GitHub pull request" : "GitHub repository page"
            return SourceInfo(source: .github, author: repo, site: "github.com", subject: title, kind: kind)
        }

        // YouTube
        if has("youtube.com") || has("youtu.be") || lower.hasSuffix("- youtube") {
            return SourceInfo(source: .youtube, author: nil, site: "youtube.com",
                              subject: strip(title, suffixes: ["- YouTube"]), kind: "YouTube video")
        }

        // Everything else: a web page (if we have a URL) or a native app window.
        let isWeb = host != nil
        return SourceInfo(source: .article, author: nil, site: site,
                          subject: strip(title, suffixes: [" - \(site)", " | \(site)"]),
                          kind: isWeb ? "web article" : "\(appName) window")
    }

    /// The note title: where it came from and who from, e.g. "X · @sama" or "LinkedIn · Acme".
    static func title(for info: SourceInfo) -> String {
        let name = info.source.displayName
        switch info.source {
        case .x, .linkedin, .reddit, .github:
            return "\(name) · \(info.author ?? fallback(info))"
        case .hackernews, .youtube:
            return "\(name) · \(info.subject.isEmpty ? "post" : info.subject)"
        case .article:
            return info.subject.isEmpty ? info.site : "\(info.site) · \(info.subject)"
        }
    }

    private static func fallback(_ info: SourceInfo) -> String {
        info.subject.isEmpty ? "post" : info.subject
    }

    // MARK: helpers

    private static func firstMatch(_ pattern: String, in text: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              m.numberOfRanges > 1, let r = Range(m.range(at: 1), in: text) else { return nil }
        return String(text[r])
    }

    /// Tweet/post text inside the curly or straight quotes of `Name on X: "..." / X`.
    private static func quoted(_ title: String) -> String? {
        firstMatch(#"[:] ["“](.+?)["”]\s*(?:/ X|\| LinkedIn)?$"#, in: title)
    }

    private static func strip(_ title: String, suffixes: [String]) -> String {
        var t = title
        for s in suffixes where t.lowercased().hasSuffix(s.lowercased()) {
            t = String(t.dropLast(s.count))
        }
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
