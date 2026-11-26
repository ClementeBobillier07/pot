#if os(macOS)
import AppKit
import SwiftUI
import PotCore

/// Development/QA harness: `Pot --render-plants <directory>` writes PNGs of SYNTHETIC plants
/// (fixed seed, simulated steady usage) and exits. It creates no windows or status item and
/// never reads logs, UserDefaults or Pot's Application Support data.
enum PlantSnapshots {
    private struct Sample { let name: String; var caption = ""; let plant: PlantState }

    @MainActor
    static func renderAndExit(to directory: String) -> Never {
        let output = URL(fileURLWithPath: directory, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            // Rows: usage rhythms on weekdays (weekends off) and one plant left idle after a month.
            let rows: [(title: String, samples: [Sample])] = [
                ("Light · 1.5 M work/day", growth(work: 1_500_000, provider: .codex)),
                ("Typical · 10 M work/day", growth(work: 10_000_000, provider: .claude)),
                ("Heavy · 40 M work/day", growth(work: 40_000_000, provider: .claude)),
                ("Idle after 30 typical days", wilting()),
            ]
            for row in rows { for sample in row.samples {
                try write(PlantView(plant: sample.plant).frame(width: 290, height: 300), name: "synthetic-\(sample.name).png", in: output)
            } }
            if let mature = rows[2].samples.last {
                for (scheme, background) in [("light", Color(white: 0.93)), ("dark", Color(white: 0.12))] {
                    try write(PlantView(plant: mature.plant).frame(width: 180, height: 225).padding(16).background(background),
                              name: "synthetic-floating-\(scheme).png", in: output)
                }
            }
            let sheet = VStack(alignment: .leading, spacing: 10) {
                Text("SYNTHETIC PLANTS · simulated usage, not real data · engine \(PlantEngine.version)").font(.system(size: 13, weight: .semibold))
                ForEach(rows, id: \.title) { row in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.title).font(.system(size: 12, weight: .medium))
                        HStack(spacing: 4) {
                            ForEach(row.samples, id: \.name) { sample in
                                VStack(spacing: 1) {
                                    PlantView(plant: sample.plant).frame(width: 170, height: 196)
                                    Text(sample.caption).font(.system(size: 10)).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }.padding(14).background(Color(white: 0.93))
            try write(sheet, name: "synthetic-contact-sheet.png", in: output)
            print("Wrote synthetic plant renders to \(output.path)")
            exit(0)
        } catch {
            fputs("Plant render failed: \(error)\n", stderr)
            exit(1)
        }
    }

    private static let start = Date(timeIntervalSince1970: 1_767_225_600) // 2026-01-01 UTC (Thursday), fixed
    private static func usage(_ provider: Provider, day: Int, work: Int64) -> UsageEvent {
        UsageEvent(id: "SYNTHETIC-\(provider.rawValue)-\(work)-\(day)", provider: provider,
                   timestamp: start.addingTimeInterval(Double(day) * 86400 + 10 * 3600), model: "SYNTHETIC", input: work, output: 0)
    }
    private static func isWeekday(_ day: Int) -> Bool { ![2, 3].contains(day % 7) } // day 0 is a Thursday

    /// Same seed, different rhythm; snapshots at midday so weekend dips show honestly.
    private static func growth(work: Int64, provider: Provider) -> [Sample] {
        var plant = PlantState(seed: 20_261_125, provider: provider, createdAt: start)
        let events = (0..<90).filter(isWeekday).map { usage(provider, day: $0, work: work) }
        var samples: [Sample] = []
        for day in [3, 7, 14, 30, 60, 90] {
            PlantEngine.advance(state: &plant, events: events, now: start.addingTimeInterval(Double(day) * 86400 + 12 * 3600))
            samples.append(Sample(name: "w\(work / 1_000_000)M-day\(day)", caption: "day \(day)", plant: plant))
        }
        return samples
    }

    /// A month of typical use every day, then no use at all, then three typical days back.
    private static func wilting() -> [Sample] {
        var plant = PlantState(seed: 7_777, provider: .codex, createdAt: start)
        var events = (0..<30).map { usage(.codex, day: $0, work: 10_000_000) }
        let lastUse = start.addingTimeInterval(29 * 86400 + 10 * 3600)
        var samples: [Sample] = []
        for idle in [0, 1, 2, 3, 4, 7] {
            PlantEngine.advance(state: &plant, events: events, now: lastUse.addingTimeInterval(Double(idle) * 86400 + 3600))
            samples.append(Sample(name: "idle\(idle)", caption: idle == 0 ? "in use" : "\(idle) day\(idle == 1 ? "" : "s") idle · health \(String(format: "%.2f", plant.health))", plant: plant))
        }
        events += (37..<40).map { usage(.codex, day: $0, work: 10_000_000) }
        PlantEngine.advance(state: &plant, events: events, now: start.addingTimeInterval(40 * 86400 + 3600))
        samples.append(Sample(name: "back3", caption: "3 days back · health \(String(format: "%.2f", plant.health))", plant: plant))
        return samples
    }

    @MainActor
    private static func write<V: View>(_ view: V, name: String, in directory: URL) throws {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let image = renderer.cgImage else { throw CocoaError(.fileWriteUnknown) }
        let bitmap = NSBitmapImageRep(cgImage: image)
        guard let data = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
        try data.write(to: directory.appendingPathComponent(name), options: .atomic)
    }
}
#endif
