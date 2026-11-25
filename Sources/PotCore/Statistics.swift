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
