import Foundation
import CSQLite

public enum StoreError: Error { case sqlite(String), unsupportedSchema(Int) }

/// Serialized by its owner (the app's background ingestion queue). No connection escapes this type.
public final class PotStore {
    private var db: OpaquePointer?
    private let encoder=JSONEncoder()
    private let decoder=JSONDecoder()
    public init(url: URL) throws {
        try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true)
        let result=sqlite3_open_v2(url.path,&db,SQLITE_OPEN_READWRITE|SQLITE_OPEN_CREATE|SQLITE_OPEN_FULLMUTEX,nil)
        guard result == SQLITE_OK else { throw StoreError.sqlite("Could not open local database") }
        _=chmodPrivate(url)
        try execute("PRAGMA journal_mode=WAL; PRAGMA synchronous=FULL; PRAGMA foreign_keys=ON; PRAGMA busy_timeout=5000;")
        let schema=try query("PRAGMA user_version").first?.first ?? "0"
        guard let version=Int(schema), version <= 1 else { throw StoreError.unsupportedSchema(Int(schema) ?? -1) }
        try execute("""
        CREATE TABLE IF NOT EXISTS profiles(id TEXT PRIMARY KEY, payload BLOB NOT NULL);
        CREATE TABLE IF NOT EXISTS usage(id TEXT PRIMARY KEY, profile TEXT NOT NULL, timestamp REAL NOT NULL, total INTEGER NOT NULL, payload BLOB NOT NULL);
        CREATE INDEX IF NOT EXISTS usage_profile_time ON usage(profile,timestamp);
        CREATE TABLE IF NOT EXISTS cursors(id TEXT PRIMARY KEY,payload BLOB NOT NULL);
        CREATE TABLE IF NOT EXISTS plants(profile TEXT PRIMARY KEY,payload BLOB NOT NULL);
        PRAGMA user_version=1;
        """)
    }
    deinit { sqlite3_close(db) }
    @discardableResult private func chmodPrivate(_ url:URL) -> Bool {
        (try? FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:url.path)) != nil
    }
    private func execute(_ sql:String) throws {
        guard sqlite3_exec(db,sql,nil,nil,nil)==SQLITE_OK else { throw StoreError.sqlite("Local database operation failed") }
    }
    private func statement(_ sql:String,_ bindings:[String]) throws -> OpaquePointer {
        var s:OpaquePointer?
        guard sqlite3_prepare_v2(db,sql,-1,&s,nil)==SQLITE_OK,let s else { throw StoreError.sqlite("Local database statement failed") }
        let transient=unsafeBitCast(-1,to:sqlite3_destructor_type.self)
        for (i,v) in bindings.enumerated() { sqlite3_bind_text(s,Int32(i+1),v,-1,transient) }
        return s
    }
    private func query(_ sql:String,_ bindings:[String]=[]) throws -> [[String]] {
        let s=try statement(sql,bindings);defer{sqlite3_finalize(s)}
        var rows=[[String]]();var result=sqlite3_step(s)
        while result==SQLITE_ROW {
            rows.append((0..<sqlite3_column_count(s)).map { i in sqlite3_column_text(s,i).map{String(cString:$0)} ?? "" })
            result=sqlite3_step(s)
        }
        guard result==SQLITE_DONE else { throw StoreError.sqlite("Local database read failed") };return rows
    }
    private func put(_ sql:String,_ bindings:[String]) throws {
        let s=try statement(sql,bindings);defer{sqlite3_finalize(s)}
        guard sqlite3_step(s)==SQLITE_DONE else { throw StoreError.sqlite("Local database write failed") }
    }
    private func encode<T:Encodable>(_ value:T) throws -> String { try encoder.encode(value).base64EncodedString() }
    private func decode<T:Decodable>(_ type:T.Type,_ value:String) throws -> T {
        guard let data=Data(base64Encoded:value) else { throw StoreError.sqlite("Invalid local record") }
        return try decoder.decode(type,from:data)
    }
    public func profiles() throws -> [LocalProfile] { try query("SELECT payload FROM profiles ORDER BY id").map{try decode(LocalProfile.self,$0[0])} }
    public func saveProfile(_ profile:LocalProfile) throws { try put("INSERT OR REPLACE INTO profiles VALUES(?,?)",[profile.id,try encode(profile)]) }
    public func events(profileID:String?=nil,since:Date?=nil,before:Date?=nil) throws -> [UsageEvent] {
        var clauses=[String](),bindings=[String]()
        if let profileID {clauses.append("profile=?");bindings.append(profileID)}
        if let since {clauses.append("timestamp>=?");bindings.append(String(since.timeIntervalSince1970))}
        if let before {clauses.append("timestamp<?");bindings.append(String(before.timeIntervalSince1970))}
        let filter=clauses.isEmpty ? "":" WHERE "+clauses.joined(separator:" AND ")
        let rows=try query("SELECT payload FROM usage"+filter+" ORDER BY timestamp,id",bindings)
        return try rows.map{try decode(UsageEvent.self,$0[0])}
    }
    /// Number of events older than `before`, without decoding payloads (cache key for old history).
    public func eventCount(profileID:String,before:Date) throws -> Int {
        Int(try query("SELECT COUNT(*) FROM usage WHERE profile=? AND timestamp<?",[profileID,String(before.timeIntervalSince1970)]).first?.first ?? "0") ?? 0
    }
    /// First/last event time and count for coverage display, without decoding payloads.
    public func coverage(profileID:String) throws -> (first:Date?,last:Date?,count:Int) {
        guard let row=try query("SELECT MIN(timestamp),MAX(timestamp),COUNT(*) FROM usage WHERE profile=?",[profileID]).first else{return (nil,nil,0)}
        return (Double(row[0]).map{Date(timeIntervalSince1970:$0)},Double(row[1]).map{Date(timeIntervalSince1970:$0)},Int(row[2]) ?? 0)
    }
    public func savePlantData(profileID:String,data:Data) throws { try put("INSERT OR REPLACE INTO plants VALUES(?,?)",[profileID,data.base64EncodedString()]) }
    public func plantData(profileID:String) throws -> Data? { try query("SELECT payload FROM plants WHERE profile=?",[profileID]).first.flatMap{Data(base64Encoded:$0[0])} }
    public func eraseAll() throws {
        try execute("BEGIN IMMEDIATE; DELETE FROM profiles; DELETE FROM usage; DELETE FROM cursors; DELETE FROM plants; COMMIT; PRAGMA wal_checkpoint(TRUNCATE); VACUUM;")
    }
    func cursor(id:String) throws -> LogCursor? { try query("SELECT payload FROM cursors WHERE id=?",[id]).first.map{try decode(LogCursor.self,$0[0])} }
    /// Cursor and all deduplicated records become durable atomically. Streaming updates replace only with a larger complete usage record.
    func commit(events:[UsageEvent],cursor:LogCursor,id:String) throws -> Int {
        try execute("BEGIN IMMEDIATE")
        do {
            var changed=0
            for candidate in events {
                var event=candidate
                let previous=try query("SELECT payload FROM usage WHERE id=?",[event.id]).first.map{try decode(UsageEvent.self,$0[0])}
                guard previous == nil || event.totalTokens > previous!.totalTokens else { continue }
                if let previous {
                    // Streaming completions must not move an already-counted call into another day/profile.
                    event.timestamp=min(previous.timestamp,event.timestamp)
                    event.accountID=previous.accountID
                }
                try put("INSERT OR REPLACE INTO usage VALUES(?,?,?,?,?)",[event.id,event.profileID,String(event.timestamp.timeIntervalSince1970),String(event.totalTokens),try encode(event)])
                changed += 1
                if try query("SELECT id FROM profiles WHERE id=?",[event.profileID]).isEmpty {
                    try saveProfile(LocalProfile(id:event.profileID,provider:event.provider,alias:event.accountID == nil ? "Local activity · unattributed" : "\(event.provider.displayName) account",createdAt:Date()))
                }
            }
            try put("INSERT OR REPLACE INTO cursors VALUES(?,?)",[id,try encode(cursor)])
            try execute("COMMIT");return changed
        } catch { try? execute("ROLLBACK");throw error }
    }
}
