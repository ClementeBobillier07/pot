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
            // One sheet per botanical variant, laid out like the owner's references:
            // growth at one reference day per day, then rest & return (half the reference times).
            for species in PlantSpecies.allCases {
                var rows: [(title: String, samples: [Sample])] = []
                for provider in Provider.allCases {
                    let seed = seed(for: species, salt: provider == .codex ? 1 : 2)
                    let name = "\(provider.displayName) · \(species.title(for: provider))"
                    rows.append((name, growth(seed: seed, provider: provider)))
                    rows.append(("\(name) · rest & return", restAndReturn(seed: seed, provider: provider)))
                }
                let sheet = VStack(alignment: .leading, spacing: 6) {
                    Text("SYNTHETIC · \(species.title(for: .codex).uppercased()) · simulated reference days, not real data").font(.system(size: 13, weight: .semibold))
                    ForEach(rows, id: \.title) { row in
                        VStack(alignment: .leading, spacing: 0) {
                            Text(row.title).font(.system(size: 11, weight: .medium))
                            HStack(spacing: 0) {
                                ForEach(row.samples, id: \.name) { sample in
                                    VStack(spacing: 0) {
                                        PlantView(plant: sample.plant).frame(width: 128, height: 160)
                                        Text(sample.caption).font(.system(size: 10)).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }.padding(14).background(Color(white: 0.97))
                try write(sheet, name: "synthetic-\(species.rawValue).png", in: output)
                if species == .classic, let full = rows[0].samples.last {
                    for (scheme, background) in [("light", Color(white: 0.93)), ("dark", Color(white: 0.12))] {
                        try write(PlantView(plant: full.plant).frame(width: 180, height: 225).padding(16).background(background),
                                  name: "synthetic-floating-\(scheme).png", in: output)
                    }
                }
            }
            print("Wrote synthetic plant renders to \(output.path)")
            exit(0)
        } catch {
            fputs("Plant render failed: \(error)\n", stderr)
            exit(1)
        }
    }

    private static let start = Date(timeIntervalSince1970: 1_767_225_600) // 2026-01-01 UTC, fixed

    /// Website illustrations: `<provider>-<variant>-<stage>.png`, 640×800 transparent, the same
    /// canvas as the app. Stage 0 ≈ day 7, 1 ≈ day 21, 2 ≈ day 45, 3 = full (day 90). Illustrative only.
    @MainActor
    static func renderLandingAndExit(to directory: String) -> Never {
        let output = URL(fileURLWithPath: directory, isDirectory: true)
        let wanted: [(Provider, PlantSpecies, [Int])] = [
            (.codex, .classic, [0, 1, 3]), (.codex, .blossom, [0, 1, 3]), (.codex, .surprise, [3]), (.codex, .copihue, [3]),
            (.claude, .classic, [3]), (.claude, .blossom, [3]), (.claude, .surprise, [3]), (.claude, .copihue, [3]),
        ]
        do {
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            for (provider, species, stages) in wanted {
                let seed = seed(for: species, salt: provider == .codex ? 1 : 2)
                for stage in stages {
                    var plant = PlantState(seed: seed, provider: provider, createdAt: start)
                    plant.growth = [7.0, 21, 45, 90][stage]
                    plant.lastUpdated = start.addingTimeInterval(Double([7, 21, 45, 90][stage]) * 86400)
                    plant.lastActivity = plant.lastUpdated
                    try write(PlantView(plant: plant).frame(width: 320, height: 400),
                              name: "\(provider.rawValue)-\(species.rawValue)-\(stage).png", in: output)
                }
            }
            print("Wrote website plant illustrations to \(output.path)")
            exit(0)
        } catch {
            fputs("Landing render failed: \(error)\n", stderr)
            exit(1)
        }
    }

    private static func seed(for species: PlantSpecies, salt: UInt64) -> UInt64 {
        var seed: UInt64 = 20_261_126 &* salt
        while PlantSpecies.of(seed: seed) != species { seed &+= 1 }
        return seed
    }
    /// One reference day (energy 1) of use every day.
    private static func usage(_ provider: Provider, days: Range<Int>) -> [UsageEvent] {
        days.map { day in
            UsageEvent(id: "SYNTHETIC-\(provider.rawValue)-\(day)", provider: provider,
                       timestamp: start.addingTimeInterval(Double(day) * 86400 + 10 * 3600), model: "SYNTHETIC",
                       input: Int64(PlantEngine.referenceDailyWork), output: 0)
        }
    }
    private static func growth(seed: UInt64, provider: Provider) -> [Sample] {
        var plant = PlantState(seed: seed, provider: provider, createdAt: start)
        let events = usage(provider, days: 0..<90)
        return [1, 3, 7, 14, 30, 45, 60, 90].map { day in
            PlantEngine.advance(state: &plant, events: events, now: start.addingTimeInterval(Double(day) * 86400 + 11 * 3600))
            return Sample(name: "day\(day)", caption: "Day \(day)", plant: plant)
        }
    }
    private static func restAndReturn(seed: UInt64, provider: Provider) -> [Sample] {
        var plant = PlantState(seed: seed, provider: provider, createdAt: start)
        var events = usage(provider, days: 0..<90)
        let lastUse = start.addingTimeInterval(89 * 86400 + 10 * 3600)
        var samples: [Sample] = []
        // The app updates continuously; advance day by day so all 90 days count as growth.
        for day in 1..<90 { PlantEngine.advance(state: &plant, events: events, now: start.addingTimeInterval(Double(day) * 86400)) }
        for (away, label) in [(0.0, "Active"), (1.5, "1.5 days away"), (3.5, "3.5 days away"), (7, "7 days away"), (15, "15 days away")] {
            PlantEngine.advance(state: &plant, events: events, now: lastUse.addingTimeInterval(away * 86400 + 3600))
            samples.append(Sample(name: "away\(away)", caption: label, plant: plant))
        }
        let back = 89 + 15
        events += usage(provider, days: back..<(back + 8))
        for (days, label) in [(1.0, "1 day back"), (3.5, "3.5 days back"), (7, "7 days back")] {
            PlantEngine.advance(state: &plant, events: events, now: start.addingTimeInterval((Double(back) + days) * 86400 + 3600))
            samples.append(Sample(name: "back\(days)", caption: label, plant: plant))
        }
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
