import XCTest
@testable import PotCore

final class IntegrationTests:XCTestCase {
    private var root:URL!
    override func setUpWithError() throws {root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)}
    override func tearDownWithError() throws {try FileManager.default.removeItem(at:root)}
    private func store() throws -> PotStore {try PotStore(url:root.appendingPathComponent("pot.sqlite"))}
    private func line(_ object:[String:Any]) throws -> Data {var data=try JSONSerialization.data(withJSONObject:object,options:[.sortedKeys]);data.append(10);return data}
    private func codex(_ input:Int,_ output:Int,_ cached:Int,_ seconds:Int=0)->[String:Any] {
        ["type":"event_msg","timestamp":String(format:"2026-11-25T12:00:%02dZ",seconds),"payload":["type":"token_count","info":["total_token_usage":["input_tokens":input,"output_tokens":output,"cached_input_tokens":cached],"last_token_usage":["input_tokens":999999,"output_tokens":999999]]]]
    }
    private func codexHeader() throws -> Data {try line(["type":"session_meta","payload":["id":"fixture-session"]])+line(["type":"turn_context","payload":["model":"gpt-5.2"]])}
    private func claude(id:String="message-1",output:Int=20,write:Int=0,cacheDetail:Bool=false)->[String:Any] {
        var usage:[String:Any]=["input_tokens":100,"output_tokens":output,"cache_read_input_tokens":30,"cache_creation_input_tokens":write]
        if cacheDetail{usage["cache_creation"]=["ephemeral_5m_input_tokens":write,"ephemeral_1h_input_tokens":0]}
        return ["type":"assistant","timestamp":"2026-11-25T12:00:00Z","requestId":"request-1","message":["id":id,"model":"claude-sonnet-4-5","usage":usage,"content":[["text":"SENSITIVE_SENTINEL never retained"]]]]
    }
    func testCodexCumulativeAndLastNeverDoubleCountAndRestartDeduplicates() throws {
        let file=root.appendingPathComponent("usage.jsonl")
        try (codexHeader()+line(codex(1000,100,200))+line(codex(1500,150,300,1))+line(codex(1500,150,300,2))).write(to:file)
        var db:PotStore?=try store()
        XCTAssertEqual(try LogIngestor(store:db!).scan(root:root,provider:.codex).insertedEvents,2)
        let events=try db!.events();XCTAssertEqual(events.reduce(0){$0+$1.totalTokens},1650)
        XCTAssertEqual(events.reduce(0){$0+$1.input},1200);XCTAssertEqual(events.reduce(0){$0+$1.cacheRead},300)
        db=nil;let reopened=try store()
        XCTAssertEqual(try LogIngestor(store:reopened).scan(root:root,provider:.codex).insertedEvents,0)
        try FileManager.default.copyItem(at:file,to:root.appendingPathComponent("copy.jsonl"))
        XCTAssertEqual(try LogIngestor(store:reopened).scan(root:root,provider:.codex).insertedEvents,0)
        XCTAssertEqual(try reopened.events().count,2)
    }
    func testPartialLineAndCursorAreCommittedTogether() throws {
        let file=root.appendingPathComponent("tail.jsonl"),db=try store(),ingestor=LogIngestor(store:db)
        let event=try line(codex(100,20,10))
        try (codexHeader()+event.prefix(event.count/2)).write(to:file)
        XCTAssertEqual(try ingestor.scanFile(file,provider:.codex).insertedEvents,0)
        let handle=try FileHandle(forWritingTo:file);try handle.seekToEnd();try handle.write(contentsOf:event.dropFirst(event.count/2));try handle.close()
        XCTAssertEqual(try ingestor.scanFile(file,provider:.codex).insertedEvents,1)
        XCTAssertEqual(try db.events().first?.totalTokens,120)
    }
    func testCounterResetEstablishesBaselineWithoutNegativeUsage() throws {
        let file=root.appendingPathComponent("reset.jsonl"),db=try store()
        try (codexHeader()+line(codex(1000,100,100))+line(codex(200,20,10,1))+line(codex(300,30,20,2))).write(to:file)
        let report=try LogIngestor(store:db).scanFile(file,provider:.codex)
        XCTAssertEqual(report.incompleteFiles,1)
        XCTAssertEqual(try db.events().reduce(0){$0+$1.totalTokens},1210)
    }
    func testTruncateAndReplacePreserveUniqueEvents() throws {
        let file=root.appendingPathComponent("rotate.jsonl"),db=try store(),i=LogIngestor(store:db)
        let contents=try codexHeader()+line(codex(100,20,10))
        try contents.write(to:file);_ = try i.scanFile(file,provider:.codex)
        try Data().write(to:file);_ = try i.scanFile(file,provider:.codex)
        try contents.write(to:file);_ = try i.scanFile(file,provider:.codex)
        try FileManager.default.removeItem(at:file);try contents.write(to:file);_ = try i.scanFile(file,provider:.codex)
        XCTAssertEqual(try db.events().count,1)
    }
    func testClaudeStreamingUpdatesReplaceMessageRatherThanAdding() throws {
        let file=root.appendingPathComponent("claude.jsonl"),db=try store(),i=LogIngestor(store:db)
        try (line(claude(output:5))+line(claude(output:20))+line(claude(output:20))).write(to:file)
        _=try i.scanFile(file,provider:.claude)
        XCTAssertEqual(try db.events().count,1);XCTAssertEqual(try db.events().first?.totalTokens,150)
        let data=try Data(contentsOf:root.appendingPathComponent("pot.sqlite"));XCTAssertFalse(String(decoding:data,as:UTF8.self).contains("SENSITIVE_SENTINEL"))
        let e=try db.events().first!;XCTAssertNil(e.accountID);XCTAssertEqual(e.profileID,Provider.claude.unattributedProfileID)
    }
    func testMalformedLinesAndSymlinksDoNotEscapeAuthorizedRoot() throws {
        let db=try store(),i=LogIngestor(store:db)
        let external=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".jsonl")
        defer{try? FileManager.default.removeItem(at:external)}
        try line(claude()).write(to:external)
        try FileManager.default.createSymbolicLink(at:root.appendingPathComponent("escape.jsonl"),withDestinationURL:external)
        try Data("not json\n".utf8).write(to:root.appendingPathComponent("malformed.jsonl"))
        let report=try i.scan(root:root,provider:.claude)
        XCTAssertEqual(report.incompleteFiles,1);XCTAssertEqual(try db.events().count,0)
    }
    func testExplicitIdentityDoesNotRelabelUnattributedHistory() throws {
        let db=try store(),file=root.appendingPathComponent("accounts.jsonl")
        var explicit=claude(id:"second");explicit["account_id"]="confirmed-account"
        try (line(claude())+line(explicit)).write(to:file)
        _=try LogIngestor(store:db).scanFile(file,provider:.claude)
        XCTAssertEqual(try db.profiles().count,2)
        XCTAssertEqual(try db.events(profileID:Provider.claude.unattributedProfileID).count,1)
    }
    func testYearUnknownSchemaAndInvalidCountersDegradeWithoutFakeUsage() throws {
        var state=ParserState()
        var object=codex(100,20,10)
        var payload=object["payload"] as! [String:Any];payload["info"]=["total_token_usage":["input_tokens":true,"output_tokens":9]];object["payload"]=payload
        XCTAssertTrue(CodexAdapter.parse(object,state:&state).incomplete)
        XCTAssertNil(CodexAdapter.parse(["type":"future-schema"],state:&state).event)
    }
    func testOversizedLineIsDiscardedAndFollowingMetricsRecovered() throws {
        let db=try store(),file=root.appendingPathComponent("oversized.jsonl")
        try (Data(repeating:65,count:4*1024*1024+1)+Data([10])+line(claude())).write(to:file)
        let report=try LogIngestor(store:db).scanFile(file,provider:.claude)
        XCTAssertEqual(report.incompleteFiles,1);XCTAssertEqual(try db.events().count,1)
    }
    func testPricesHaveExactCacheSemanticsAndMissingCategoriesStayPartial() throws {
        let catalog=try PriceCatalog.bundled()
        let event=UsageEvent(id:"price",provider:.codex,timestamp:Date(),model:"gpt-5.2",input:800_000,output:100_000,cacheRead:200_000)
        XCTAssertEqual(catalog.estimate([event]).amount,Decimal(string:"2.835"));XCTAssertFalse(catalog.estimate([event]).partial)
        var unknown=event;unknown.model="not-a-real-supported-model"
        XCTAssertNil(catalog.estimate([unknown]).amount);XCTAssertTrue(catalog.estimate([unknown]).partial)
        let ambiguous=UsageEvent(id:"cache",provider:.claude,timestamp:Date(),model:"claude-sonnet-4-5",input:100,output:10,cacheWrite:100)
        XCTAssertTrue(catalog.estimate([ambiguous]).partial)
        let explicit=UsageEvent(id:"cache-exact",provider:.claude,timestamp:Date(),model:"claude-sonnet-4-5",input:100,output:10,cacheWrite:100,cacheWrite5m:100,cacheWrite1h:0)
        XCTAssertEqual(catalog.estimate([explicit]).amount,Decimal(string:"0.000825"));XCTAssertFalse(catalog.estimate([explicit]).partial)
    }
    func testSevenCalendarDaysIncludesZerosAndTimezoneBoundaries() throws {
        let catalog=try PriceCatalog.bundled(),now=MetricDate.parse("2026-11-25T02:00:00Z")!,zone=TimeZone(identifier:"America/Santiago")!
        let e=UsageEvent(id:"day",provider:.codex,timestamp:MetricDate.parse("2026-11-25T01:00:00Z")!,model:"gpt-5.2",input:100,output:5)
        let days=UsageStatistics.lastSevenDays(events:[e],now:now,timeZone:zone,catalog:catalog)
        XCTAssertEqual(days.count,7);XCTAssertEqual(days.dropLast().reduce(0){$0+$1.tokens},0);XCTAssertEqual(days.last?.tokens,105)
        var c=Calendar(identifier:.gregorian);c.timeZone=zone;XCTAssertEqual(c.component(.day,from:days.last!.date),24)
    }
    func testDatabasePersistsPlantProfileAndErasesOnlyItsOwnTables() throws {
        let db=try store(),profile=LocalProfile(id:"test",provider:.codex,alias:"My plant")
        try db.saveProfile(profile);try db.savePlantData(profileID:profile.id,data:Data([1,2,3]))
        XCTAssertEqual(try db.plantData(profileID:profile.id),Data([1,2,3]));XCTAssertEqual(try db.profiles().first?.alias,"My plant")
        try db.eraseAll();XCTAssertTrue(try db.profiles().isEmpty);XCTAssertNil(try db.plantData(profileID:profile.id))
    }
    func testUsageTotalSaturatesInsteadOfCrashing() {
        let event=UsageEvent(id:"large",provider:.codex,timestamp:Date(),model:"unknown",input:Int64.max,output:Int64.max)
        XCTAssertEqual(event.totalTokens,Int64.max)
    }
    func testDiscoveryUsesCustomRootsWithoutReadingAuthenticationFiles() throws {
        let home=root.appendingPathComponent("home"),custom=root.appendingPathComponent("custom")
        try FileManager.default.createDirectory(at:custom.appendingPathComponent("sessions"),withIntermediateDirectories:true)
        try FileManager.default.createDirectory(at:custom.appendingPathComponent("projects"),withIntermediateDirectories:true)
        try Data("DO_NOT_READ_SECRET".utf8).write(to:custom.appendingPathComponent("auth.json"))
        XCTAssertEqual(SourceDiscovery.defaultRoots(provider:.codex,environment:["CODEX_HOME":custom.path],home:home),[custom.appendingPathComponent("sessions")])
        XCTAssertEqual(SourceDiscovery.defaultRoots(provider:.claude,environment:["CLAUDE_CONFIG_DIR":custom.path],home:home),[custom.appendingPathComponent("projects")])
    }
    func testOversizedUnterminatedLineResumesWithoutUnboundedAllocation() throws {
        let db=try store(),file=root.appendingPathComponent("long-tail.jsonl"),i=LogIngestor(store:db)
        try Data(repeating:65,count:33*1024*1024).write(to:file)
        XCTAssertTrue(try i.scanFile(file,provider:.claude).truncatedWork)
        let append=try FileHandle(forWritingTo:file);try append.seekToEnd();try append.write(contentsOf:Data([10])+line(claude()));try append.close()
        XCTAssertEqual(try i.scanFile(file,provider:.claude).insertedEvents,1)
        XCTAssertEqual(try db.events().count,1)
    }
    func testClaudeRequestIDArrivingLaterDoesNotDuplicateMessage() throws {
        let db=try store(),file=root.appendingPathComponent("partial-id.jsonl")
        var earlier=claude(output:5);earlier.removeValue(forKey:"requestId")
        try (line(earlier)+line(claude(output:20))).write(to:file)
        _=try LogIngestor(store:db).scanFile(file,provider:.claude)
        XCTAssertEqual(try db.events().count,1);XCTAssertEqual(try db.events().first?.totalTokens,150)
    }
    func testStreamingCompletionKeepsOriginalDayAndAccountAttribution() throws {
        let db=try store(),file=root.appendingPathComponent("midnight.jsonl")
        var first=claude(output:5);first["timestamp"]="2026-11-24T23:59:59Z"
        var final=claude(output:20);final["timestamp"]="2026-11-25T00:00:01Z";final["account_id"]="later-account"
        try (line(first)+line(final)).write(to:file)
        _=try LogIngestor(store:db).scanFile(file,provider:.claude)
        let event=try XCTUnwrap(db.events().first)
        XCTAssertEqual(event.timestamp,MetricDate.parse("2026-11-24T23:59:59Z"));XCTAssertNil(event.accountID)
        XCTAssertEqual(try db.profiles().count,1)
    }
    func testLastOnlyCodexRequiresStableRequestToAvoidRateLimitDoubleCount() throws {
        var state=ParserState(session:"session",model:"gpt-5.2")
        let usage:[String:Any]=["input_tokens":100,"output_tokens":20,"cached_input_tokens":10]
        let ambiguous:[String:Any]=["type":"event_msg","timestamp":"2026-11-25T12:00:00Z","payload":["type":"token_count","info":["last_token_usage":usage]]]
        XCTAssertTrue(CodexAdapter.parse(ambiguous,state:&state).incomplete)
        XCTAssertNil(CodexAdapter.parse(ambiguous,state:&state).event)
        let safe:[String:Any]=["type":"event_msg","timestamp":"2026-11-25T12:00:00Z","payload":["type":"token_count","info":["last_token_usage":usage,"request_id":"request"]]]
        var later=safe;later["timestamp"]="2026-11-25T12:00:01Z"
        XCTAssertEqual(CodexAdapter.parse(safe,state:&state).event?.id,CodexAdapter.parse(later,state:&state).event?.id)
    }
    func testModernCodexRecordsDeduplicateLegacyAndCopiedParentOwnership() throws {
        let db=try store(),file=root.appendingPathComponent("modern.jsonl")
        let usage:[String:Any]=["input_tokens":100,"output_tokens":20,"cached_input_tokens":10]
        let record:[String:Any]=["type":"token_usage_record","timestamp":"2026-11-25T12:00:00Z","payload":["thread_id":"fixture-session","response_id":"response-1","usage":usage,"thread_token_usage":usage]]
        var inherited=record;inherited["payload"]=["thread_id":"parent-session","response_id":"parent-response","usage":usage,"thread_token_usage":usage]
        try (codexHeader()+line(inherited)+line(record)+line(codex(100,20,10))).write(to:file)
        _=try LogIngestor(store:db).scanFile(file,provider:.codex)
        XCTAssertEqual(try db.events().count,1);XCTAssertEqual(try db.events().first?.totalTokens,120)
        XCTAssertTrue(try db.events(since:MetricDate.parse("2026-11-26T00:00:00Z")).isEmpty)
        XCTAssertEqual(try db.events(profileID:Provider.codex.unattributedProfileID,since:MetricDate.parse("2026-11-25T00:00:00Z")).count,1)
    }
    func testLegacyForkWithoutProvableOwnershipIsQuarantined() throws {
        let db=try store(),file=root.appendingPathComponent("fork.jsonl")
        let header=try line(["type":"session_meta","payload":["id":"child","forked_from_id":"parent"]])+line(["type":"turn_context","payload":["model":"gpt-5.2"]])
        try (header+line(codex(100,20,10))+line(codex(200,40,20,1))).write(to:file)
        let report=try LogIngestor(store:db).scanFile(file,provider:.codex)
        XCTAssertEqual(report.incompleteFiles,1);XCTAssertTrue(try db.events().isEmpty)
    }
    func testCurrentCodexCacheCreationIsASubsetOfInputAndUsesVerifiedWritePrice() throws {
        var state=ParserState(session:"session",model:"gpt-6.2-sol")
        let usage:[String:Any]=["input_tokens":1000,"output_tokens":100,"cached_input_tokens":200,"cache_creation_tokens":300]
        let raw:[String:Any]=["type":"token_usage_record","timestamp":"2026-11-25T12:00:00Z","payload":["thread_id":"session","response_id":"response-write","usage":usage,"thread_token_usage":usage]]
        let event=try XCTUnwrap(CodexAdapter.parse(raw,state:&state).event)
        XCTAssertEqual(event.input,500);XCTAssertEqual(event.totalTokens,1100);XCTAssertEqual(event.cacheWrite,300)
        let value=try PriceCatalog.bundled().estimate([event])
        XCTAssertEqual(value.amount,Decimal(string:"0.00277"));XCTAssertFalse(value.partial)
    }
    func testExtremePublicUsageCannotOverflowPriceThresholdOrCacheDurations() throws {
        let catalog=try PriceCatalog.bundled()
        let huge=UsageEvent(id:"large-threshold",provider:.codex,timestamp:Date(),model:"gpt-5.4",input:Int64.max,output:0,cacheRead:Int64.max,cacheWrite:Int64.max)
        XCTAssertNil(catalog.estimate([huge]).amount)
        let durations=UsageEvent(id:"large-duration",provider:.claude,timestamp:Date(),model:"claude-sonnet-4-5",input:0,output:0,cacheWrite:1,cacheWrite5m:Int64.max,cacheWrite1h:Int64.max)
        XCTAssertTrue(catalog.estimate([durations]).partial)
    }
    func testLegacyAndModernPartialCopiesShareCanonicalCumulativeIdentity() throws {
        let db=try store(),legacy=root.appendingPathComponent("legacy-only.jsonl"),modern=root.appendingPathComponent("modern-only.jsonl"),i=LogIngestor(store:db)
        let usage:[String:Any]=["input_tokens":100,"output_tokens":20,"cached_input_tokens":10]
        let record:[String:Any]=["type":"token_usage_record","timestamp":"2026-11-25T12:00:01Z","payload":["thread_id":"fixture-session","response_id":"response-copied","usage":usage,"thread_token_usage":usage]]
        try (codexHeader()+line(codex(100,20,10))+line(record)).write(to:legacy)
        try (codexHeader()+line(record)).write(to:modern)
        _=try i.scanFile(legacy,provider:.codex);_=try i.scanFile(modern,provider:.codex)
        XCTAssertEqual(try db.events().count,1);XCTAssertEqual(try db.events().first?.totalTokens,120)
    }
    func testKnownPremiumServiceTierKeepsReferenceValueExplicitlyPartial() throws {
        var state=ParserState(session:"session",model:"gpt-5.2")
        _=CodexAdapter.parse(["type":"turn_context","payload":["model":"gpt-5.2","service_tier":"priority"]],state:&state)
        let event=try XCTUnwrap(CodexAdapter.parse(codex(100,20,10),state:&state).event)
        XCTAssertTrue(try PriceCatalog.bundled().estimate([event]).partial)
    }
}
