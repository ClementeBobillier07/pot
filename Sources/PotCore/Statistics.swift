import Foundation

public struct DailyUsage:Identifiable,Sendable {
    public var date:Date
    public var tokens:Int64
    public var estimatedUSD:Decimal?
    public var partial:Bool
    public var id:Date {date}
}
public enum UsageStatistics {
    public static func lastSevenDays(events:[UsageEvent],now:Date=Date(),timeZone:TimeZone = .current,catalog:PriceCatalog)->[DailyUsage] {
        var calendar=Calendar(identifier:.gregorian);calendar.timeZone=timeZone
        let today=calendar.startOfDay(for:now)
        return (-6...0).map{offset in
            let start=calendar.date(byAdding:.day,value:offset,to:today)!
            let end=calendar.date(byAdding:.day,value:1,to:start)!
            let daily=events.filter{$0.timestamp>=start && $0.timestamp<end && $0.timestamp<=now}
            let estimate=catalog.estimate(daily)
            let tokens=daily.reduce(Int64(0)){sum,event in let (next,overflow)=sum.addingReportingOverflow(event.totalTokens);return overflow ? Int64.max:next}
            return DailyUsage(date:start,tokens:tokens,estimatedUSD:estimate.amount,partial:estimate.partial)
        }
    }
}

/// Totals for one display period (today, 7 days, 30 days or all available history).
public struct PeriodSummary: Sendable, Equatable {
    public var tokens: Int64
    public var input: Int64
    public var output: Int64
    public var cacheRead: Int64
    public var cacheWrite: Int64
    public var estimatedUSD: Decimal?
    public var partial: Bool
    public var events: Int
    public var firstEvent: Date?
    public var lastEvent: Date?
    public static let empty = PeriodSummary(tokens: 0, input: 0, output: 0, cacheRead: 0, cacheWrite: 0, estimatedUSD: 0, partial: false, events: 0, firstEvent: nil, lastEvent: nil)
}

public enum UsagePeriod: String, CaseIterable, Sendable, Identifiable {
    case today, week, month, all
    public var id: String { rawValue }
    public var title: String {
        switch self { case .today: return "Today"; case .week: return "7 days"; case .month: return "30 days"; case .all: return "All" }
    }
    /// Start of the period in the given calendar; nil means all available history.
    public func start(now: Date, timeZone: TimeZone = .current) -> Date? {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = timeZone
        let today = calendar.startOfDay(for: now)
        switch self {
        case .today: return today
        case .week: return calendar.date(byAdding: .day, value: -6, to: today)
        case .month: return calendar.date(byAdding: .day, value: -29, to: today)
        case .all: return nil
        }
    }
}

extension UsageStatistics {
    public static func summary(events: [UsageEvent], period: UsagePeriod, now: Date = Date(), timeZone: TimeZone = .current, catalog: PriceCatalog) -> PeriodSummary {
        let start = period.start(now: now, timeZone: timeZone)
        let selected = events.filter { event in event.timestamp <= now && (start.map { event.timestamp >= $0 } ?? true) }
        return summary(selected, catalog: catalog)
    }
    public static func summary(_ events: [UsageEvent], catalog: PriceCatalog) -> PeriodSummary {
        func add(_ a: Int64, _ b: Int64) -> Int64 { let (r, o) = a.addingReportingOverflow(max(0, b)); return o ? Int64.max : r }
        var s = PeriodSummary.empty
        for e in events {
            s.tokens = add(s.tokens, e.totalTokens); s.input = add(s.input, e.input); s.output = add(s.output, e.output)
            s.cacheRead = add(s.cacheRead, e.cacheRead); s.cacheWrite = add(s.cacheWrite, e.cacheWrite)
            s.firstEvent = min(s.firstEvent ?? e.timestamp, e.timestamp); s.lastEvent = max(s.lastEvent ?? e.timestamp, e.timestamp)
        }
        s.events = events.count
        let estimate = catalog.estimate(events)
        s.estimatedUSD = estimate.amount; s.partial = estimate.partial
        return s
    }
}

/// Local, user-initiated export: daily aggregates and garden state per plant. No event IDs,
/// account pseudonyms, paths or transcript content are included.
public enum GardenExport {
    public struct Plant: Codable {
        public var alias: String
        public var provider: Provider
        public var daily: [Day]
        public var plant: PlantState?
    }
    public struct Day: Codable {
        public var date: String
        public var tokens: Int64, input: Int64, output: Int64, cacheRead: Int64, cacheWrite: Int64
        public var estimatedUSD: Decimal?
        public var estimatePartial: Bool
    }
    public struct Document: Codable {
        public var format = "pot-garden-export-v1"
        public var exportedAt: Date
        public var priceReference: String
        public var note = "Token counts come from local Codex/Claude Code records. USD values are estimated API-equivalent reference prices, not a bill."
        public var plants: [Plant]
    }
    public static func make(profiles: [LocalProfile], events: [UsageEvent], plants: [String: PlantState], catalog: PriceCatalog, now: Date = Date(), timeZone: TimeZone = .current) throws -> Data {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = timeZone
        let formatter = DateFormatter(); formatter.calendar = calendar; formatter.timeZone = timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd"
        let byProfile = Dictionary(grouping: events, by: \.profileID)
        let output = profiles.map { profile -> Plant in
            let days = Dictionary(grouping: byProfile[profile.id] ?? [], by: { formatter.string(from: $0.timestamp) })
            let daily = days.keys.sorted().map { key -> Day in
                let s = UsageStatistics.summary(days[key]!, catalog: catalog)
                return Day(date: key, tokens: s.tokens, input: s.input, output: s.output, cacheRead: s.cacheRead, cacheWrite: s.cacheWrite, estimatedUSD: s.estimatedUSD, estimatePartial: s.partial)
            }
            return Plant(alias: profile.alias, provider: profile.provider, daily: daily, plant: plants[profile.id])
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(Document(exportedAt: now, priceReference: catalog.version, plants: output))
    }
}
