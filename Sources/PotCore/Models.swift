import Foundation

public enum Provider: String, Codable, CaseIterable, Sendable {
    case codex, claude
    public var displayName: String { self == .codex ? "Codex" : "Claude Code" }
    public var unattributedProfileID: String { "local:\(rawValue):unattributed" }
}

public struct LocalProfile: Codable, Identifiable, Sendable {
    public var id: String
    public var provider: Provider
    public var alias: String
    public var email: String?
    public var createdAt: Date
    public init(id: String, provider: Provider, alias: String, email: String? = nil, createdAt: Date = Date()) {
        self.id=id; self.provider=provider; self.alias=alias; self.email=email; self.createdAt=createdAt
    }
}

public struct UsageEvent: Codable, Sendable, Equatable {
    public var id: String
    public var provider: Provider
    public var accountID: String?
    public var timestamp: Date
    public var model: String
    /// Non-overlapping categories. Codex cached input is subtracted from input.
    public var input: Int64
    public var output: Int64
    public var cacheRead: Int64
    public var cacheWrite: Int64
    public var cacheWrite5m: Int64?
    public var cacheWrite1h: Int64?
    public var pricingIncomplete: Bool
    public var totalTokens: Int64 { [input,output,cacheRead,cacheWrite].reduce(0) { sum, value in
        let (next,overflow)=sum.addingReportingOverflow(max(0,value));return overflow ? Int64.max:next
    } }
    public var profileID: String { accountID ?? provider.unattributedProfileID }
    public init(id: String, provider: Provider, accountID: String? = nil, timestamp: Date, model: String, input: Int64, output: Int64, cacheRead: Int64 = 0, cacheWrite: Int64 = 0, cacheWrite5m: Int64? = nil, cacheWrite1h: Int64? = nil, pricingIncomplete: Bool = false) {
        self.id=id;self.provider=provider;self.accountID=accountID;self.timestamp=timestamp;self.model=model
        self.input=max(0,input);self.output=max(0,output);self.cacheRead=max(0,cacheRead);self.cacheWrite=max(0,cacheWrite)
        self.cacheWrite5m=cacheWrite5m;self.cacheWrite1h=cacheWrite1h;self.pricingIncomplete=pricingIncomplete
    }
}

/// Stable local pseudonym, not a cryptographic security boundary. Never hash transcript content.
public func metricID(_ text: String) -> String {
    var a: UInt64 = 14695981039346656037
    var b: UInt64 = 7809847782465536322
    for c in text.utf8 { a = (a ^ UInt64(c)) &* 1099511628211; b = (b ^ UInt64(c)) &* 14029467366897019727 }
    return String(format:"%016llx%016llx", a,b)
}

enum MetricDate {
    private static let lock=NSLock()
    private static let fractional:ISO8601DateFormatter={let f=ISO8601DateFormatter();f.formatOptions=[.withInternetDateTime,.withFractionalSeconds];return f}()
    private static let standard:ISO8601DateFormatter={let f=ISO8601DateFormatter();f.formatOptions=[.withInternetDateTime];return f}()
    static func parse(_ text: String?) -> Date? {
        guard let text else { return nil }
        lock.lock();defer{lock.unlock()}
        return fractional.date(from:text) ?? standard.date(from:text)
    }
}
