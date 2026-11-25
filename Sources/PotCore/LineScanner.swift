import Foundation
#if os(Linux)
import Glibc
#else
import Darwin
#endif

/// Splits a byte stream into JSONL records and hands over only records that can carry usage metrics.
///
/// Real Codex rollouts contain tool outputs and compaction records of 10–17 MiB, and Claude Code
/// stores large prompt blobs. Those records never carry usage, so they are skipped without being
/// buffered and without marking the file partial. A record is only "incomplete" when it was
/// relevant (it carries a usage-bearing type marker) and could not be parsed within limits.
struct LineScanner {
    private enum Mode { case undecided, keep, skip }

    let provider: Provider
    let lineLimit: Int
    private(set) var incomplete = false
    private var buffer = Data()
    private var mode: Mode
    private var oversized = false

    /// Codex writes `"type"` within the first ~90 bytes of every record (verified on real logs).
    static let codexDecisionWindow = 512
    static let codexMarkers: [[UInt8]] = ["token_usage_record", "session_meta", "turn_context", "token_count", "thread_settings_applied"].map { Array("\"type\":\"\($0)\"".utf8) }
    static let claudeMarker = Array("\"type\":\"assistant\"".utf8)
    static let typeMarker = Array("\"type\":\"".utf8)

    init(provider: Provider, resumeDiscarding: Bool = false, lineLimit: Int = 4 * 1024 * 1024) {
        self.provider = provider
        self.lineLimit = lineLimit
        self.mode = resumeDiscarding ? .skip : .undecided
    }

    /// True while a record has started but its newline has not been seen.
    var midLine: Bool { mode != .undecided || !buffer.isEmpty }
    /// True when the unfinished record is being discarded and need not be re-read.
    var discardingCurrentLine: Bool { mode == .skip || oversized }

    /// Feeds bytes. `record` receives each complete relevant record; `lineEnded` receives the
    /// offset (relative to this chunk) just after each newline.
    mutating func feed(_ bytes: UnsafeRawBufferPointer, record: (Data) -> Void, lineEnded: (Int) -> Void) {
        guard let base = bytes.baseAddress else { return }
        var start = 0
        let count = bytes.count
        while start < count {
            let remaining = count - start
            let found = memchr(base + start, 10, remaining)
            let end = found.map { UnsafeRawPointer($0) - base } ?? count
            append(UnsafeRawBufferPointer(start: base + start, count: end - start))
            guard found != nil else { return }
            finishLine(record: record)
            lineEnded(end + 1)
            start = end + 1
        }
    }

    /// A compressed archive is complete at EOF, so a final record without newline is processed.
    mutating func finish(record: (Data) -> Void) {
        if midLine { finishLine(record: record) }
    }

    private mutating func append(_ part: UnsafeRawBufferPointer) {
        guard part.count > 0 else { return }
        switch mode {
        case .skip: return
        case .keep:
            if oversized { return }
            if buffer.count + part.count > lineLimit {
                buffer.append(contentsOf: part.prefix(max(0, lineLimit - buffer.count)))
                // An oversized record matters only if it is usage-bearing.
                if isRelevant(buffer, complete: false) { incomplete = true }
                oversized = true
                buffer.removeAll(keepingCapacity: false)
                return
            }
            buffer.append(contentsOf: part)
        case .undecided:
            buffer.append(contentsOf: part)
            guard provider == .codex else { mode = .keep; enforceLimit(); return }
            if buffer.count >= Self.codexDecisionWindow { decideCodex() }
        }
    }

    private mutating func enforceLimit() {
        guard buffer.count > lineLimit else { return }
        if isRelevant(buffer, complete: false) { incomplete = true }
        oversized = true
        buffer.removeAll(keepingCapacity: false)
    }

    private mutating func decideCodex() {
        let window = buffer.prefix(Self.codexDecisionWindow)
        if Self.codexMarkers.contains(where: { contains(window, $0) }) { mode = .keep; enforceLimit() }
        else if contains(window, Self.typeMarker) { mode = .skip; buffer.removeAll(keepingCapacity: true) }
        else { mode = .keep; enforceLimit() } // Unknown layout: keep conservatively.
    }

    private mutating func finishLine(record: (Data) -> Void) {
        defer { buffer.removeAll(keepingCapacity: buffer.count <= 1 << 20); mode = .undecided; oversized = false }
        guard mode != .skip, !oversized, !buffer.isEmpty else { return }
        if mode == .undecided, provider == .codex {
            decideCodex()
            guard mode == .keep, !oversized else { return }
        }
        guard isRelevant(buffer, complete: true) else { return }
        record(buffer)
    }

    private func isRelevant(_ data: Data, complete: Bool) -> Bool {
        switch provider {
        case .claude: return contains(data, Self.claudeMarker)
        case .codex: return Self.codexMarkers.contains { contains(data.prefix(Self.codexDecisionWindow), $0) } || !contains(data.prefix(Self.codexDecisionWindow), Self.typeMarker)
        }
    }

    private func contains(_ data: Data, _ needle: [UInt8]) -> Bool {
        data.withUnsafeBytes { haystack in
            needle.withUnsafeBytes { n in
                guard let h = haystack.baseAddress, let p = n.baseAddress, haystack.count >= n.count else { return false }
                return memmem(h, haystack.count, p, n.count) != nil
            }
        }
    }
}
