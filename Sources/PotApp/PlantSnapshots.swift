#if os(macOS)
import AppKit
import SwiftUI
import PotCore

/// Development/QA harness: `Pot --render-plants <directory>` writes PNGs of SYNTHETIC plants
/// (fixed seed, simulated steady usage) and exits. It creates no windows or status item and
/// never reads logs, UserDefaults or Pot's Application Support data.
enum PlantSnapshots {
    private struct Sample { let name: String; let plant: PlantState }

    @MainActor
    static func renderAndExit(to directory: String) -> Never {
        let output = URL(fileURLWithPath: directory, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            var samples: [Sample] = []
            for provider in Provider.allCases {
                samples += growth(provider: provider)
            }
            for sample in samples {
                try write(PlantView(plant: sample.plant).frame(width: 290, height: 300), name: "synthetic-\(sample.name).png", in: output)
            }
            // Floating-panel size (180 pt wide), on light and dark desktops.
            if let mature = samples.first(where: { $0.name == "claude-day120" }) {
                for (scheme, background) in [("light", Color(white: 0.93)), ("dark", Color(white: 0.12))] {
                    try write(PlantView(plant: mature.plant).frame(width: 180, height: 225).padding(16).background(background),
                              name: "synthetic-floating-\(scheme).png", in: output)
                }
            }
            // One contact sheet for quick review.
            let sheet = VStack(alignment: .leading, spacing: 8) {
                Text("SYNTHETIC PLANTS · simulated usage, not real data").font(.system(size: 13, weight: .semibold))
                ForEach(Provider.allCases, id: \.rawValue) { provider in
                    HStack(spacing: 4) {
                        ForEach(samples.filter { $0.plant.provider == provider }, id: \.name) { sample in
                            VStack(spacing: 2) {
                                PlantView(plant: sample.plant).frame(width: 190, height: 220)
                                Text(sample.name).font(.system(size: 10)).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }.padding(12).background(Color(white: 0.93))
            try write(sheet, name: "synthetic-contact-sheet.png", in: output)
            print("Wrote synthetic plant renders to \(output.path)")
            exit(0)
        } catch {
            fputs("Plant render failed: \(error)\n", stderr)
            exit(1)
        }
    }

    /// Weekday usage at a steady personal rhythm; weekends rest. Ages in days.
    private static func growth(provider: Provider) -> [Sample] {
        let start = Date(timeIntervalSince1970: 1_767_225_600) // 2026-01-01 UTC, fixed
        var plant = PlantState(seed: 20_261_125, provider: provider, createdAt: start)
        var events: [UsageEvent] = []
        var samples = [Sample(name: "\(provider.rawValue)-day0", plant: plant)]
        let checkpoints = [3, 14, 45, 120, 365]
        for day in 0..<365 {
            if day % 7 < 5 {
                let tokens: Int64 = Int64(2_000_000 + (day % 5) * 400_000)
                events.append(UsageEvent(id: "SYNTHETIC-\(provider.rawValue)-\(day)", provider: provider,
                                         timestamp: start.addingTimeInterval(Double(day) * 86400 + 10 * 3600),
                                         model: "SYNTHETIC", input: tokens / 10, output: tokens / 50, cacheRead: tokens - tokens / 10 - tokens / 50))
            }
            PlantEngine.advance(state: &plant, events: events, now: start.addingTimeInterval(Double(day + 1) * 86400))
            if checkpoints.contains(day + 1) {
                samples.append(Sample(name: "\(provider.rawValue)-day\(day + 1)", plant: plant))
                if day + 1 == 45 {
                    // Same plant after a month without activity: tired, never dead.
                    var resting = plant
                    PlantEngine.advance(state: &resting, events: events, now: start.addingTimeInterval(Double(day + 31) * 86400))
                    samples.append(Sample(name: "\(provider.rawValue)-rest30", plant: resting))
                }
            }
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
