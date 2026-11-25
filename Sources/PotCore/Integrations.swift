import Foundation

struct TokenVector: Codable, Equatable {
    var input:Int64=0, output:Int64=0, cache:Int64=0, write:Int64=0
    static func read(_ object:[String:Any]) -> TokenVector? {
        guard let input=count(object["input_tokens"]),let output=count(object["output_tokens"]) else { return nil }
        let cache=count(object["cached_input_tokens"]) ?? 0
        let write=count(object["cache_creation_tokens"]) ?? 0
        guard cache+write <= input else { return nil }
        return TokenVector(input:input,output:output,cache:cache,write:write)
    }
    func delta(from old:TokenVector) -> TokenVector? {
        guard input>=old.input,output>=old.output,cache>=old.cache,write>=old.write else{return nil}
        let d=TokenVector(input:input-old.input,output:output-old.output,cache:cache-old.cache,write:write-old.write)
        guard d.cache+d.write<=d.input else{return nil};return d
    }
}

func count(_ value:Any?) -> Int64? {
    guard let n=value as? NSNumber,CFGetTypeID(n) != CFBooleanGetTypeID() else{return nil}
    let d=n.doubleValue
    guard d.isFinite,d>=0,d<=1_000_000_000_000_000,d.rounded()==d else{return nil}
    return n.int64Value
}

struct ParserState:Codable {
    var session:String?
    var model:String="unknown"
    var cumulative:TokenVector?
    var forkNeedsBaseline=false
    var legacyFork=false
    var usesUsageRecords=false
    var nonstandardPricing=false
}

struct ParseResult {
    var event:UsageEvent?
    var incomplete=false
}

/// Adapters intentionally inspect only schema/identity/usage keys; textual content is never retained.
enum CodexAdapter {
    static func parse(_ o:[String:Any],state:inout ParserState) -> ParseResult {
        let p=o["payload"] as? [String:Any] ?? [:]
        if let tier=p["service_tier"] as? String {state.nonstandardPricing = !["default","standard","auto"].contains(tier)}
        if let fast=p["fast_mode"] as? Bool,fast {state.nonstandardPricing=true}
        if p["type"] as? String == "thread_settings_applied",let settings=p["thread_settings"] as? [String:Any],let tier=settings["service_tier"] as? String {state.nonstandardPricing = !["default","standard","auto"].contains(tier)}
        if o["type"] as? String == "session_meta" {
            if let id=p["id"] as? String {state.session=id}
            state.forkNeedsBaseline=(p["forked_from_id"] as? String) != nil
            state.legacyFork=state.forkNeedsBaseline
            return ParseResult()
        }
        if o["type"] as? String == "turn_context" {
            if let model=p["model"] as? String {state.model=model};return ParseResult()
        }
        if o["type"] as? String == "token_usage_record" {
            guard let session=state.session,let owner=p["thread_id"] as? String ?? p["session_id"] as? String,let response=p["response_id"] as? String,
                  let date=MetricDate.parse(o["timestamp"] as? String),let raw=p["usage"] as? [String:Any],let usage=TokenVector.read(raw) else{return ParseResult(incomplete:true)}
            guard owner==session else{return ParseResult()} // copied parent/fork history
            guard let cumulative=(p["thread_token_usage"] as? [String:Any]).flatMap({TokenVector.read($0)}) else{return ParseResult(incomplete:true)}
            let alreadyCounted=cumulative==state.cumulative
            state.usesUsageRecords=true
            state.cumulative=cumulative
            guard !alreadyCounted else{return ParseResult()}
            if let model=p["model"] as? String {state.model=model}
            let account=(p["account_id"] as? String).map{"codex:account:"+metricID($0)}
            _=response // required stable response metadata; canonical cumulative key also bridges legacy-only copies
            let key="\(session)|c:\(cumulative.input):\(cumulative.output):\(cumulative.cache):\(cumulative.write)"
            return ParseResult(event:UsageEvent(id:"codex:usage:"+metricID(key),provider:.codex,accountID:account,timestamp:date,model:state.model,input:usage.input-usage.cache-usage.write,output:usage.output,cacheRead:usage.cache,cacheWrite:usage.write,pricingIncomplete:state.model=="unknown" || state.nonstandardPricing),incomplete:state.model=="unknown")
        }
        guard o["type"] as? String == "event_msg",p["type"] as? String == "token_count" else{return ParseResult()}
        if state.usesUsageRecords{return ParseResult()}
        if state.legacyFork{return ParseResult(incomplete:true)} // no provable boundary between inherited and new cumulative history
        guard let info=p["info"] as? [String:Any] else{return ParseResult(incomplete:false)} // null rate-limit-only event
        guard let date=MetricDate.parse(o["timestamp"] as? String) else{return ParseResult(incomplete:true)}
        if let model=info["model"] as? String ?? p["model"] as? String {state.model=model}
        var tokens:TokenVector
        var signature:String
        var stableRequest:String?
        if let raw=info["total_token_usage"] as? [String:Any] {
            guard let cumulative=TokenVector.read(raw) else{return ParseResult(incomplete:true)}
            let previous=state.cumulative ?? TokenVector()
            state.cumulative=cumulative
            if state.forkNeedsBaseline {state.forkNeedsBaseline=false;return ParseResult(incomplete:true)}
            guard let delta=cumulative.delta(from:previous) else{return ParseResult(incomplete:true)}
            tokens=delta
            signature="c:\(cumulative.input):\(cumulative.output):\(cumulative.cache):\(cumulative.write)"
        } else if let raw=info["last_token_usage"] as? [String:Any],let last=TokenVector.read(raw) {
            // Without cumulative counters or a request identity, a rate-limit update can
            // repeat the same last call at another timestamp. Quarantine that ambiguity.
            guard let request=info["request_id"] as? String ?? p["request_id"] as? String else{return ParseResult(incomplete:true)}
            tokens=last;signature="request:\(request)";stableRequest=request
        } else{return ParseResult(incomplete:true)}
        guard tokens.input+tokens.output>0 else{return ParseResult()}
        let session=state.session ?? "unidentified-session"
        let identity=stableRequest.map{"\(session)|request:\($0)"} ?? "\(session)|\(signature)"
        let id="codex:usage:"+metricID(identity)
        let account=(p["account_id"] as? String ?? o["account_id"] as? String).map{"codex:account:"+metricID($0)}
        return ParseResult(event:UsageEvent(id:id,provider:.codex,accountID:account,timestamp:date,model:state.model,input:tokens.input-tokens.cache-tokens.write,output:tokens.output,cacheRead:tokens.cache,cacheWrite:tokens.write,pricingIncomplete:state.model=="unknown" || state.nonstandardPricing),incomplete:state.model=="unknown" || state.session==nil)
    }
}

enum ClaudeAdapter {
    static func parse(_ o:[String:Any],state:inout ParserState) -> ParseResult {
        guard o["type"] as? String == "assistant",let m=o["message"] as? [String:Any],let u=m["usage"] as? [String:Any] else{return ParseResult()}
        guard let input=count(u["input_tokens"]),let output=count(u["output_tokens"]),let date=MetricDate.parse(o["timestamp"] as? String),let messageID=m["id"] as? String else{return ParseResult(incomplete:true)}
        let cache=count(u["cache_read_input_tokens"]) ?? 0
        let write=count(u["cache_creation_input_tokens"]) ?? 0
        let creation=u["cache_creation"] as? [String:Any]
        let five=count(creation?["ephemeral_5m_input_tokens"])
        let hour=count(creation?["ephemeral_1h_input_tokens"])
        let model=m["model"] as? String ?? "unknown"
        // A stable assistant message ID also deduplicates partial lines where requestId arrives later.
        let id="claude:"+metricID(messageID)
        let account=(o["account_id"] as? String).map{"claude:account:"+metricID($0)}
        let ambiguous=write>0 && (five == nil || hour == nil || five!+hour! != write)
        let tier=u["service_tier"] as? String ?? m["service_tier"] as? String ?? o["service_tier"] as? String
        let nonstandard=tier.map{!["standard","default","auto"].contains($0)} ?? false
        let fast=u["inference_geo"] as? String != nil || u["speed"] as? String == "fast" || o["fastMode"] as? Bool == true
        return ParseResult(event:UsageEvent(id:id,provider:.claude,accountID:account,timestamp:date,model:model,input:input,output:output,cacheRead:cache,cacheWrite:write,cacheWrite5m:five,cacheWrite1h:hour,pricingIncomplete:ambiguous || model=="unknown" || nonstandard || fast),incomplete:model=="unknown")
    }
}

import CoreFoundation
