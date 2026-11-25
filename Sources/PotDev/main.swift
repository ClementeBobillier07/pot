import Foundation
import PotCore

// This separate executable is never bundled into Pot.app. It cannot write the
// production database and never represents simulated events as provider data.
let arguments = Array(CommandLine.arguments.dropFirst())
if arguments.first == "benchmark-import" {
    let megabytes=min(1024,max(1,arguments.count>1 ? Int(arguments[1]) ?? 100:100))
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent("pot-synthetic-benchmark-"+UUID().uuidString)
    try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
    defer{try? FileManager.default.removeItem(at:directory)}
    let file=directory.appendingPathComponent("SYNTHETIC.jsonl")
    guard FileManager.default.createFile(atPath:file.path,contents:nil) else{throw CocoaError(.fileWriteUnknown)}
    let writer=try FileHandle(forWritingTo:file)
    let filler=String(repeating:"SYNTHETIC-NOT-USER-CONTENT ",count:160)
    var records=0,bytes=0
    while bytes<megabytes*1024*1024 {
        let object:[String:Any]=["type":"assistant","timestamp":"2026-11-25T12:00:00Z","message":["id":"SYNTHETIC-\(records)","model":"claude-sonnet-4-5","usage":["input_tokens":100,"output_tokens":20,"cache_read_input_tokens":30],"content":[["type":"text","text":filler]]]]
        var data=try JSONSerialization.data(withJSONObject:object);data.append(10)
        try writer.write(contentsOf:data);bytes += data.count;records += 1
    }
    try writer.close()
    let store=try PotStore(url:directory.appendingPathComponent("benchmark.sqlite")),ingestor=LogIngestor(store:store)
    var inserted=0,passes=0
    let start=Date()
    while true {
        let report=try ingestor.scanFile(file,provider:.claude);passes += 1;inserted += report.insertedEvents
        if !report.truncatedWork {break}
        guard passes<100 else{fatalError("Synthetic benchmark did not converge")}
    }
    let elapsed=Date().timeIntervalSince(start)
    let events=try store.events()
    guard events.count==records,inserted==records,events.reduce(Int64(0),{$0+$1.totalTokens})==Int64(records)*150 else{fatalError("Synthetic import totals differ")}
    let repeated=try ingestor.scanFile(file,provider:.claude)
    guard repeated.insertedEvents==0,try store.events().count==records else{fatalError("Synthetic replay duplicated usage")}
    print("SYNTHETIC IMPORT BENCHMARK · no real user logs or production database")
    print("\(bytes) bytes · \(records) unique messages · \(passes) incremental passes · replay added 0")
    print(String(format:"Import %.3f seconds · %.2f MiB/s",elapsed,Double(bytes)/1048576/max(0.001,elapsed)))
    exit(0)
}
if arguments.first == "--detect" {
    // No public identity is printed, even when the installed client exposes one.
    // The default discovery path never starts optional Codex app-server.
    for agent in SourceDiscovery.detect() {
        let auth = agent.authenticated.map { $0 ? "yes" : "no" } ?? "unknown"
        let identity = agent.account.map { $0.id != nil || $0.email != nil } ?? false
        print("provider=\(agent.provider.rawValue) installed=\(agent.executable != nil) version=\(agent.version ?? "unknown") authenticated=\(auth) hasPublicIdentity=\(identity) roots=\(agent.roots.count) status=\(agent.status)")
    }
    exit(0)
}
guard arguments.first == "simulate" else {
    print("Pot development tools\nUsage: swift run pot-dev simulate [days=365] [seed=42] [codex|claude]\n       swift run pot-dev --detect (sanitized real local detection)\n       swift run pot-dev benchmark-import [MiB=100] (synthetic logs only)")
    exit(arguments.isEmpty ? 0 : 2)
}
let duration = min(3650, max(1, arguments.count > 1 ? Int(arguments[1]) ?? 365 : 365))
let seed = arguments.count > 2 ? UInt64(arguments[2]) ?? 42 : 42
let provider: Provider = arguments.count > 3 && arguments[3] == "claude" ? .claude : .codex
let start = Date(timeIntervalSince1970: 1_735_689_600)
var plant = PlantState(seed: seed, provider: provider, createdAt: start)
var events: [UsageEvent] = []
let began = Date()
for day in 0..<duration {
    if day % 7 < 5 {
        events.append(UsageEvent(id: "SYNTHETIC-\(day)", provider: provider,
                                 timestamp: start.addingTimeInterval(Double(day) * 86400 + 9 * 3600),
                                 model: "SYNTHETIC-NOT-REAL", input: 100_000, output: 20_000, cacheRead: 50_000))
    }
    PlantEngine.advance(state: &plant, events: events, now: start.addingTimeInterval(Double(day + 1) * 86400))
}
let elapsed = Date().timeIntervalSince(began)
let data = try JSONEncoder().encode(plant)
print("SYNTHETIC SIMULATION · no real accounts, usage, or billing")
print("\(duration) days · seed \(seed) · \(provider.displayName)")
print("\(plant.organs.count) live organs · \(plant.retiredOrgans) retired · \(data.count) state bytes")
print(String(format: "Elapsed %.3f seconds · health %.3f · historical maturity %.3f", elapsed, plant.health, plant.historicalMaturity))
if let destination = ProcessInfo.processInfo.environment["POT_SIMULATION_OUTPUT"], !destination.isEmpty {
    // Explicit local developer opt-in; never defaults to Application Support.
    let url = URL(fileURLWithPath: destination).standardizedFileURL
    guard !url.path.contains("/Application Support/Pot/") else {
        fputs("Refusing production data destination\n", stderr)
        exit(2)
    }
    try data.write(to: url, options: .atomic)
    print("Synthetic state written to \(url.path)")
}
