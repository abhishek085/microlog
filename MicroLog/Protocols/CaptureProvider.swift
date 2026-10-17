import Foundation

protocol CaptureProvider {
    /// Returns the current captured context, or nil if nothing capturable / private.
    func currentContext() async throws -> CaptureContext?
}

/// Allow/deny configuration used by capture providers.
struct CapturePolicy {
    var minimumReadTime: TimeInterval = 20
    var minimumWordCount: Int = 150
    var allowedApps: Set<String> = []
    var allowedDomains: Set<String> = ["x.com", "twitter.com", "linkedin.com"]
    var deniedDomains: Set<String> = []
    var deniedApps: Set<String> = []

    func isAllowed(domain: String, app: String?) -> Bool {
        let d = domain.lowercased()
        if deniedDomains.contains(where: { d.contains($0) }) { return false }
        if let app, deniedApps.contains(app) { return false }
        if !allowedDomains.isEmpty {
            // Allow if any allowed domain suffix matches, OR a known news/blog domain (default open).
            let allowed = allowedDomains.contains { d == $0 || d.hasSuffix("." + $0) }
            if !allowed && !allowedDomains.isEmpty {
                // Conservative: unknown domains require explicit allow.
                return false
            }
        }
        return true
    }
}
