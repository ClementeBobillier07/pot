import Foundation

struct LogCursor:Codable {
    var identity:String
    var offset:UInt64=0
    var prefixLength:Int=0
    var prefixDigest:String=""
    var modificationTime:Double=0
    var parser=ParserState()
    var incomplete=false
    var discardingLine=false
}

public struct ScanReport:Sendable {
    public var insertedEvents:Int=0
    public var filesScanned:Int=0
    public var incompleteFiles:Int=0
    public var newestEvent:Date?
    public var truncatedWork=false
    public var bytesRead:UInt64=0
    public init() {}
}

public final class LogIngestor {
    private let store:PotStore
    public init(store:PotStore){self.store=store}
    /// Bounded 32 MiB per plain file/pass, 4 MiB per relevant line (16 MiB in archives), 10,000 files/pass; unfinished work is resumed.
    /// Archived `.jsonl.zst` files are decoded whole (bounded at 4 GiB output) and count their compressed size against the pass budget.
    public func scan(root:URL,provider:Provider) throws -> ScanReport {
        let fm=FileManager.default
        let canonical=root.standardizedFileURL.resolvingSymlinksInPath()
        var directory:ObjCBool=false
        guard fm.fileExists(atPath:canonical.path,isDirectory:&directory),directory.boolValue else{throw CocoaError(.fileNoSuchFile)}
        let keys:Set<URLResourceKey>=[.isRegularFileKey,.isSymbolicLinkKey,.isDirectoryKey]
        var report=ScanReport()
        var enumerationFailed=false
        guard let files=fm.enumerator(at:canonical,includingPropertiesForKeys:Array(keys),options:[.skipsHiddenFiles],errorHandler:{_,_ in enumerationFailed=true;return true}) else{throw CocoaError(.fileReadNoPermission)}
        for case let url as URL in files {
            if report.filesScanned>=10_000 || report.bytesRead>=64*1024*1024 {report.truncatedWork=true;report.incompleteFiles += 1;break}
            let values=try url.resourceValues(forKeys:keys)
            if values.isSymbolicLink==true {files.skipDescendants();continue}
            guard values.isRegularFile==true else{continue}
            let compressed=url.lastPathComponent.hasSuffix(".jsonl.zst")
            guard compressed || url.pathExtension=="jsonl" else{continue}
            let resolved=url.resolvingSymlinksInPath().standardizedFileURL
            guard resolved.path.hasPrefix(canonical.path+"/") else{report.incompleteFiles += 1;continue}
            do {
                let r=try compressed ? scanCompressedFile(resolved,provider:provider) : scanFile(resolved,provider:provider)
                report.filesScanned += 1;report.insertedEvents += r.insertedEvents;report.incompleteFiles += r.incompleteFiles
                report.bytesRead += r.bytesRead
                report.truncatedWork = report.truncatedWork || r.truncatedWork
                if let d=r.newestEvent {report.newestEvent=max(report.newestEvent ?? d,d)}
            } catch {report.incompleteFiles += 1}
        }
        if enumerationFailed {report.incompleteFiles += 1};return report
    }
    public func scanFile(_ url:URL,provider:Provider) throws -> ScanReport {
        let attributes=try FileManager.default.attributesOfItem(atPath:url.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular else{throw CocoaError(.fileReadUnsupportedScheme)}
        let identity="\(attributes[.systemNumber] ?? ""):\(attributes[.systemFileNumber] ?? "")"
        let length=(attributes[.size] as? NSNumber)?.uint64Value ?? 0
        let modificationTime=(attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let key=metricID(provider.rawValue+":"+url.standardizedFileURL.path)
        var cursor=try store.cursor(id:key) ?? LogCursor(identity:identity)
        let file=try FileHandle(forReadingFrom:url);defer{try? file.close()}
        if cursor.identity != identity || length<cursor.offset || (length==cursor.offset && modificationTime != cursor.modificationTime) {cursor=LogCursor(identity:identity)}
        if cursor.prefixLength>0 {
            let prefix=try file.read(upToCount:cursor.prefixLength) ?? Data()
            if prefixSignature(prefix) != cursor.prefixDigest {cursor=LogCursor(identity:identity)}
        }
        if cursor.offset==length {var r=ScanReport();r.incompleteFiles=cursor.incomplete ? 1:0;return r}
        try file.seek(toOffset:cursor.offset)
        var events=[UsageEvent](),consumed:UInt64=0,complete=cursor.offset
        var scanner=LineScanner(provider:provider,resumeDiscarding:cursor.discardingLine)
        var parser=cursor.parser
        var parseIncomplete=false
        let budget:UInt64=32*1024*1024
        while consumed<budget {
            // Drain Foundation temporaries (JSON objects, Data) per chunk; without it peak memory reached ~3 GB on real logs.
            let done:Bool=try autoreleasepool {
                let chunk=try file.read(upToCount:256*1024) ?? Data()
                if chunk.isEmpty{return true}
                let chunkStart=cursor.offset+consumed
                consumed += UInt64(chunk.count)
                chunk.withUnsafeBytes { raw in
                    scanner.feed(raw, record: { line in
                        let r=Self.parse(line,provider:provider,state:&parser)
                        if let event=r.event{events.append(event)};parseIncomplete = parseIncomplete || r.incomplete
                    }, lineEnded: { complete=chunkStart+UInt64($0) })
                }
                return false
            }
            if done{break}
        }
        cursor.parser=parser
        cursor.incomplete = cursor.incomplete || parseIncomplete || scanner.incomplete
        // A trailing record still being written is simply re-read next pass; it is not data loss.
        let oversized=scanner.discardingCurrentLine
        let position=try file.offset()
        // A skipped (irrelevant or oversized) record need not be re-read on the next pass.
        if oversized {complete=position}
        cursor.discardingLine=oversized
        cursor.offset=complete
        cursor.prefixLength=Int(min(cursor.offset,4096))
        try file.seek(toOffset:0)
        cursor.prefixDigest=prefixSignature(try file.read(upToCount:cursor.prefixLength) ?? Data())
        cursor.modificationTime=modificationTime
        var report=ScanReport();report.filesScanned=1
        report.insertedEvents=try store.commit(events:events,cursor:cursor,id:key)
        report.newestEvent=events.map(\.timestamp).max()
        report.bytesRead=consumed
        report.truncatedWork=position<length
        report.incompleteFiles=(cursor.incomplete || report.truncatedWork) ? 1:0
        return report
    }
    static func parse(_ line:Data,provider:Provider,state:inout ParserState)->ParseResult {
        guard let object=(try? JSONSerialization.jsonObject(with:line)) as? [String:Any] else{return ParseResult(incomplete:true)}
        return provider == .codex ? CodexAdapter.parse(object,state:&state) : ClaudeAdapter.parse(object,state:&state)
    }
    /// Archived rollouts are immutable: decode once, commit atomically, skip while size/mtime/inode are unchanged.
    public func scanCompressedFile(_ url:URL,provider:Provider) throws -> ScanReport {
        let attributes=try FileManager.default.attributesOfItem(atPath:url.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular else{throw CocoaError(.fileReadUnsupportedScheme)}
        let identity="\(attributes[.systemNumber] ?? ""):\(attributes[.systemFileNumber] ?? "")"
        let length=(attributes[.size] as? NSNumber)?.uint64Value ?? 0
        let modificationTime=(attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let key=metricID(provider.rawValue+":"+url.standardizedFileURL.path)
        if let cursor=try store.cursor(id:key),cursor.identity==identity,cursor.offset==length,cursor.modificationTime==modificationTime {
            var r=ScanReport();r.incompleteFiles=cursor.incomplete ? 1:0;return r
        }
        var cursor=LogCursor(identity:identity)
        var scanner=LineScanner(provider:provider,lineLimit:16*1024*1024)
        var events=[UsageEvent](),parser=ParserState(),parseIncomplete=false
        let handle:(Data)->Void={ line in
            let r=Self.parse(line,provider:provider,state:&parser)
            if let event=r.event{events.append(event)};parseIncomplete = parseIncomplete || r.incomplete
        }
        do {
            try ZstdStream.decompress(url,maximumOutput:4*1024*1024*1024) { raw in autoreleasepool { scanner.feed(raw,record:handle,lineEnded:{_ in}) } }
            scanner.finish(record:handle)
        } catch {
            // Corrupt, truncated or oversized archive: keep what was decoded, report partial.
            parseIncomplete=true
        }
        cursor.parser=parser
        cursor.incomplete=parseIncomplete || scanner.incomplete
        cursor.offset=length
        cursor.modificationTime=modificationTime
        var report=ScanReport();report.filesScanned=1
        report.insertedEvents=try store.commit(events:events,cursor:cursor,id:key)
        report.newestEvent=events.map(\.timestamp).max()
        report.bytesRead=length
        report.incompleteFiles=cursor.incomplete ? 1:0
        return report
    }
    /// Fingerprint only structural first-line metadata, never prompt/response/code content.
    private func prefixSignature(_ data:Data)->String {
        guard let end=data.firstIndex(of:10),let object=(try? JSONSerialization.jsonObject(with:data.prefix(upTo:end))) as? [String:Any] else{return ""}
        let payload=object["payload"] as? [String:Any] ?? [:]
        let message=object["message"] as? [String:Any] ?? [:]
        let fields=[object["type"] as? String,object["timestamp"] as? String,payload["id"] as? String,message["id"] as? String,object["sessionId"] as? String]
        return metricID(fields.map{$0 ?? ""}.joined(separator:"|"))
    }
}
