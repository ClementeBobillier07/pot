import Foundation

public struct PriceRate:Codable,Sendable {
    public var provider:Provider
    public var model:String
    public var referenceDate:String
    public var effectiveFrom:String
    public var source:String
    public var input:Decimal
    public var output:Decimal
    public var cacheRead:Decimal
    public var cacheWrite:Decimal?
    public var cacheWrite5m:Decimal?
    public var cacheWrite1h:Decimal?
    public var maxInputTokens:Int64?
}
public struct ValueEstimate:Sendable {
    public var amount:Decimal?
    public var partial:Bool
    public var pricedEvents:Int
    public var totalEvents:Int
    public var referenceDate:String
}
public struct PriceCatalog:Codable,Sendable {
    public var version:String
    public var verifiedAt:String
    public var rates:[PriceRate]
    public static func bundled() throws -> PriceCatalog {
        #if os(macOS)
        // SwiftPM's synthesized Bundle.module searches build-tree/main-bundle roots;
        // a distributable .app keeps its resource bundle under Contents/Resources.
        if let resource=Bundle.main.url(forResource:"Pot_PotCore",withExtension:"bundle"),
           let bundle=Bundle(url:resource),let url=bundle.url(forResource:"prices-v1",withExtension:"json") {
            return try JSONDecoder().decode(PriceCatalog.self,from:Data(contentsOf:url))
        }
        if Bundle.main.bundleURL.pathExtension=="app" {throw CocoaError(.fileNoSuchFile)}
        #endif
        guard let url=Bundle.module.url(forResource:"prices-v1",withExtension:"json") else{throw CocoaError(.fileNoSuchFile)}
        return try JSONDecoder().decode(PriceCatalog.self,from:Data(contentsOf:url))
    }
    /// Exact model match. Prompt-length tiers (e.g. Haiku 5.5 above 100K prompt tokens) pick the
    /// narrowest tier whose `maxInputTokens` covers this request's prompt; an untiered rate covers any size.
    /// When only capped tiers exist and the prompt exceeds them all, the event stays unpriced.
    func rate(for event:UsageEvent)->PriceRate? {
        let prompt=Decimal(event.input)+Decimal(event.cacheRead)+Decimal(event.cacheWrite)
        let candidates=rates.filter{$0.model==event.model && $0.provider==event.provider}
        let capped=candidates.filter{$0.maxInputTokens != nil}.sorted{$0.maxInputTokens! < $1.maxInputTokens!}
        if let tier=capped.first(where:{prompt <= Decimal($0.maxInputTokens!)}) {return tier}
        return candidates.last{$0.maxInputTokens == nil}
    }
    /// Snapshot reference prices; not a historical invoice. Exact model matching only.
    public func estimate(_ events:[UsageEvent])->ValueEstimate {
        var amount:Decimal=0,priced=0,partial=false
        for event in events {
            guard let rate=rate(for:event) else{partial=true;continue}
            var value=Decimal(event.input)*rate.input + Decimal(event.output)*rate.output + Decimal(event.cacheRead)*rate.cacheRead
            if event.cacheWrite>0 {
                if event.provider == .codex,let writeRate=rate.cacheWrite {value += Decimal(event.cacheWrite)*writeRate}
                else if let five=event.cacheWrite5m,let hour=event.cacheWrite1h, Decimal(five)+Decimal(hour)==Decimal(event.cacheWrite),let fiveRate=rate.cacheWrite5m,let hourRate=rate.cacheWrite1h {
                    value += Decimal(five)*fiveRate + Decimal(hour)*hourRate
                } else{partial=true}
            }
            amount += value / 1_000_000;priced += 1;partial = partial || event.pricingIncomplete
        }
        return ValueEstimate(amount:events.isEmpty ? Decimal(0):(priced==0 ? nil:amount),partial:partial,pricedEvents:priced,totalEvents:events.count,referenceDate:verifiedAt)
    }
}
