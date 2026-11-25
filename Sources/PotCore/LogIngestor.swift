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
    /// Bounded 32 MiB per file/pass, 4 MiB per line, 10,000 files/pass; unfinished work is resumed.
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
            if url.pathExtension=="zst" {report.incompleteFiles += 1;continue}
            guard url.pathExtension=="jsonl" else{continue}
            let resolved=url.resolvingSymlinksInPath().standardizedFileURL
            guard resolved.path.hasPrefix(canonical.path+"/") else{report.incompleteFiles += 1;continue}
            do {
                let r=try scanFile(resolved,provider:provider)
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
        var buffer=Data(),events=[UsageEvent](),consumed:UInt64=0,complete=cursor.offset
        var oversized=cursor.discardingLine
        var absolute=cursor.offset
        let budget:UInt64=32*1024*1024
        while consumed<budget {
            let chunk=try file.read(upToCount:64*1024) ?? Data()
            if chunk.isEmpty{break};consumed += UInt64(chunk.count)
            for byte in chunk {
                absolute += 1
                if byte==10 {
                    complete=absolute
                    if oversized {cursor.incomplete=true}
                    else if !buffer.isEmpty {
                        if let object=(try? JSONSerialization.jsonObject(with:buffer)) as? [String:Any] {
                            let r=provider == .codex ? CodexAdapter.parse(object,state:&cursor.parser) : ClaudeAdapter.parse(object,state:&cursor.parser)
                            if let event=r.event{events.append(event)};cursor.incomplete = cursor.incomplete || r.incomplete
                        } else {cursor.incomplete=true}
                    }
                    buffer.removeAll(keepingCapacity:true);oversized=false
                } else if !oversized {
                    if buffer.count<4*1024*1024 {buffer.append(byte)}
                    else {oversized=true;buffer.removeAll(keepingCapacity:true)}
                }
            }
        }
        let partial = !buffer.isEmpty || oversized
        let position=try file.offset()
        if oversized {complete=position;cursor.incomplete=true}
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
        report.incompleteFiles=(cursor.incomplete || partial || report.truncatedWork) ? 1:0
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
