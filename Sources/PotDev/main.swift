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
if arguments.first == "reconcile" {
    // Reads this Mac's real Codex/Claude logs into a throwaway database and prints only
    // aggregate counts (no paths, prompts, identities or content). Never touches Pot's garden.
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("pot-reconcile-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = try PotStore(url: directory.appendingPathComponent("reconcile.sqlite"))
    let ingestor = LogIngestor(store: store)
    let catalog = try PriceCatalog.bundled()
    for provider in Provider.allCases {
        let roots = SourceDiscovery.defaultRoots(provider: provider)
        let began = Date()
        var passes = 0, incomplete = 0, files = 0
        var bytes: UInt64 = 0
        for root in roots {
            var rootPasses = 0
            while true {
                let report = try ingestor.scan(root: root, provider: provider)
                passes += 1; rootPasses += 1; bytes += report.bytesRead
                if !report.truncatedWork || report.bytesRead == 0 || rootPasses >= 500 { incomplete += report.incompleteFiles; files += report.filesScanned; break }
            }
        }
        let elapsed = Date().timeIntervalSince(began)
        let events = try store.events().filter { $0.provider == provider }
        var byModel: [String: (n: Int, input: Int64, output: Int64, read: Int64, write: Int64)] = [:]
        for e in events {
            var row = byModel[e.model] ?? (0, 0, 0, 0, 0)
            row.n += 1; row.input += e.input; row.output += e.output; row.read += e.cacheRead; row.write += e.cacheWrite
            byModel[e.model] = row
        }
        let total = events.reduce(Int64(0)) { $0 + $1.totalTokens }
        let estimate = catalog.estimate(events)
        let profiles = Set(events.map(\.profileID)).map { $0.hasPrefix("local:") ? "unattributed" : "account-evidence" }
        print("== \(provider.displayName): roots=\(roots.count) passes=\(passes) bytesRead=\(bytes) files(last pass)=\(files) incompleteFiles=\(incomplete) elapsed=\(String(format: "%.2f", elapsed))s")
        print("events=\(events.count) totalTokens=\(total) profiles=\(profiles.sorted())")
        for (model, row) in byModel.sorted(by: { $0.value.n > $1.value.n }) {
            print("  \(model): n=\(row.n) input=\(row.input) output=\(row.output) cacheRead=\(row.read) cacheWrite=\(row.write)")
        }
        print("  estimatedUSD=\(estimate.amount.map { "\($0)" } ?? "unavailable") partial=\(estimate.partial) priced=\(estimate.pricedEvents)/\(estimate.totalEvents)")
    }
    // Replays real local usage into a throwaway plant born at the first observed event.
    for provider in Provider.allCases {
        let events = try store.events().filter { $0.provider == provider }
        guard let first = events.map(\.timestamp).min() else { continue }
        var plant = PlantState(seed: 42, provider: provider, createdAt: first)
        var day = first
        let end = Date()
        while day < end {
            day = min(end, day.addingTimeInterval(86400))
            PlantEngine.advance(state: &plant, events: events, now: day)
        }
        let credited = plant.days.map { String(format: "%.2f", $0.credited) }.joined(separator: " ")
        let references = plant.days.map { String(format: "%.0fk", $0.reference / 1000) }
        print("plant[\(provider.rawValue)] ageDays=\(Int(Date().timeIntervalSince(first) / 86400)) organs=\(plant.organs.count) leaves=\(plant.organs.filter { $0.kind == .leaf }.count) flowers=\(plant.organs.filter { $0.kind == .flower }.count) branches=\(plant.organs.filter { $0.kind == .branch || $0.kind == .stem }.count) maturity=\(String(format: "%.2f", plant.historicalMaturity)) health=\(String(format: "%.2f", plant.health))")
        print("  daily credited energy: \(credited)")
        print("  reference first/last: \(references.first ?? "-") → \(references.last ?? "-")")
    }
    let replayStart = Date()
    var replayed = 0
    for provider in Provider.allCases { for root in SourceDiscovery.defaultRoots(provider: provider) { replayed += try ingestor.scan(root: root, provider: provider).insertedEvents } }
    print("replay inserted=\(replayed) in \(String(format: "%.2f", Date().timeIntervalSince(replayStart)))s")
    exit(0)
}
if arguments.first == "--detect" {
    // No public identity is printed, even when the installed client exposes one.
    // The default discovery path never starts optional Codex app-server.
    // `--detect --accounts` also runs the optional Codex account lookup; values are still not printed.
    for agent in SourceDiscovery.detect(includeAccountDetails: arguments.contains("--accounts")) {
        let auth = agent.authenticated.map { $0 ? "yes" : "no" } ?? "unknown"
        let identity = agent.account.map { $0.id != nil || $0.email != nil } ?? false
        let a = agent.account
        print("provider=\(agent.provider.rawValue) installed=\(agent.executable != nil) version=\(agent.version ?? "unknown") authenticated=\(auth) hasPublicIdentity=\(identity) hasEmail=\(a?.email != nil) plan=\(a?.plan ?? "-") method=\(a?.method ?? "-") roots=\(agent.roots.count) status=\(agent.status)")
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
