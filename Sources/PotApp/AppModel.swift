#if os(macOS)
import AppKit
import SwiftUI
import ServiceManagement
import CoreServices
import PotCore

struct AccountSnapshot {
    var profile: LocalProfile
    var plant: PlantState
    var days: [DailyUsage]
    var lastActivity: Date?
    var coverage: String
    var priceReference: String
    /// Today / 7 days / 30 days from the in-memory 45-day window. "All" is loaded on demand.
    var periods: [UsagePeriod: PeriodSummary] = [:]
    var historyStart: Date?
    var recordCount = 0
    var lastRead = Date()
}

/// Confined to AppModel's serial ingestion queue; never touched concurrently.
private final class GardenWorker: @unchecked Sendable {
    private var store: PotStore?
    /// Set when the last scan stopped with history left to import.
    var pendingImport = false
    /// Summary of events older than the 45-day window, keyed by window start day and their count.
    private var olderHistory: [String: (key: String, summary: PeriodSummary)] = [:]
    func database() throws -> PotStore {
        if let store { return store }
        let folder = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("Pot", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let value = try PotStore(url: folder.appendingPathComponent("garden.sqlite"))
        store = value
        return value
    }

    func scan(roots: [Provider: [URL]], detections: [AgentDetection], now: Date) throws -> [AccountSnapshot] {
        let db = try database()
        pendingImport = false
        let catalog = try PriceCatalog.bundled()
        let ingestor = LogIngestor(store: db)
        var availability: [Provider: Bool] = [:]
        var coverage: [Provider: String] = [:]
        for provider in Provider.allCases {
            let sources = roots[provider] ?? []
            var healthy = !sources.isEmpty
            var found = false
            var importing = false
            for root in sources {
                do {
                    // Keep resuming bounded passes for a few seconds so a first import of a large
                    // history finishes in one or two scans instead of one 64 MiB pass per minute.
                    let deadline = Date().addingTimeInterval(8)
                    var report = try ingestor.scan(root: root, provider: provider)
                    while report.truncatedWork && report.bytesRead > 0 && Date() < deadline { report = try ingestor.scan(root: root, provider: provider) }
                    found = found || report.filesScanned > 0
                    // Reschedule immediately only while passes make progress; a stalled pass is partial coverage.
                    if report.truncatedWork && report.bytesRead > 0 { importing = true; pendingImport = true }
                    else if report.incompleteFiles > 0 || report.truncatedWork { healthy = false }
                } catch { healthy = false }
            }
            availability[provider] = healthy && found && !importing
            coverage[provider] = importing ? "Importing local history… · health protected" : !healthy ? "Source unavailable or partial · health protected" : !found ? "No compatible usage yet · health protected" : "Local records · account attribution may be incomplete"
            let detected = detections.first { $0.provider == provider }
            // The signed-in account is shown in onboarding/settings only. It never gets its own plant:
            // Claude Code logs carry no per-event account, so such a plant could never grow, and the
            // current login does not prove who produced past records. Plants follow log evidence.
            // Placeholder only when this provider has no plant yet; logs with explicit account evidence create their own.
            if (detected?.executable != nil || !sources.isEmpty), !(try db.profiles()).contains(where: { $0.provider == provider }) {
                try db.saveProfile(LocalProfile(id: provider.unattributedProfileID, provider: provider, alias: "Local activity · unattributed", createdAt: now))
            }
        }
        return try db.profiles().map { profile in
            let events = try db.events(profileID: profile.id, since: now.addingTimeInterval(-45 * 86400))
            let plant: PlantState
            if let data = try db.plantData(profileID: profile.id) {
                // A decoding failure must surface; replacing it would silently reset a garden.
                let stored = try JSONDecoder().decode(PlantState.self, from: data)
                // A plant from an older growth engine is re-grown from its birth with the current
                // rules, keeping its seed (look) and birth date. Only the young beta plants are affected.
                plant = stored.engineVersion < PlantEngine.version
                    ? PlantState(seed: stored.seed, provider: stored.provider, createdAt: stored.createdAt)
                    : stored
            } else {
                plant = PlantState(seed: UInt64.random(in: 1...UInt64.max), provider: profile.provider, createdAt: profile.createdAt)
            }
            var updated = plant
            PlantEngine.advance(state: &updated, events: events, now: now, dataAvailable: availability[profile.provider] ?? false)
            try db.savePlantData(profileID: profile.id, data: JSONEncoder().encode(updated))
            let range = try db.coverage(profileID: profile.id)
            var periods: [UsagePeriod: PeriodSummary] = [:]
            for period in [UsagePeriod.today, .week, .month] {
                periods[period] = UsageStatistics.summary(events: events, period: period, now: now, timeZone: .current, catalog: catalog)
            }
            // "All" = cached older history + the in-memory window, refreshed on every scan.
            let windowStart = now.addingTimeInterval(-45 * 86400)
            let olderKey = "\(Int(windowStart.timeIntervalSince1970 / 86400))|\(try db.eventCount(profileID: profile.id, before: windowStart))"
            if olderHistory[profile.id]?.key != olderKey {
                olderHistory[profile.id] = (olderKey, UsageStatistics.summary(try db.events(profileID: profile.id, before: windowStart), catalog: catalog))
            }
            let window = UsageStatistics.summary(events.filter { $0.timestamp >= windowStart && $0.timestamp <= now }, catalog: catalog)
            periods[.all] = olderHistory[profile.id]!.summary.combined(with: window)
            return AccountSnapshot(profile: profile, plant: updated,
                days: UsageStatistics.lastSevenDays(events: events, now: now, timeZone: .current, catalog: catalog),
                lastActivity: events.filter { $0.timestamp <= now }.map(\.timestamp).max(),
                coverage: coverage[profile.provider] ?? "No source available · health protected", priceReference: catalog.verifiedAt,
                periods: periods, historyStart: range.first, recordCount: range.count, lastRead: now)
        }
        // Stable garden order: provider, then plants with account evidence, then alias.
        .sorted { a, b in
            let ka = (Provider.allCases.firstIndex(of: a.profile.provider) ?? 0, a.profile.id.hasPrefix("local:") ? 1 : 0, a.profile.alias.lowercased())
            let kb = (Provider.allCases.firstIndex(of: b.profile.provider) ?? 0, b.profile.id.hasPrefix("local:") ? 1 : 0, b.profile.alias.lowercased())
            return ka < kb
        }
    }

    func eraseAll() throws {
        olderHistory = [:]
        try database().eraseAll()
    }

    func exportData(now: Date) throws -> Data {
        let db = try database()
        let profiles = try db.profiles()
        var plants: [String: PlantState] = [:]
        for profile in profiles { if let data = try db.plantData(profileID: profile.id) { plants[profile.id] = try JSONDecoder().decode(PlantState.self, from: data) } }
        return try GardenExport.make(profiles: profiles, events: try db.events(), plants: plants, catalog: try PriceCatalog.bundled(), now: now)
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var snapshots: [AccountSnapshot] = []
    @Published var detections: [AgentDetection] = []
    @Published var busy = false
    @Published var enabledProviders = Set(Provider.allCases.filter { !UserDefaults.standard.bool(forKey: "disabled.\($0.rawValue)") })
    @Published var message: String?
    @Published var showSettings = false
    /// Overview of every plant instead of one plant's details.
    @Published var showGrid = false
    /// Direction of the last plant switch (−1 previous, +1 next), so views slide the right way.
    @Published private(set) var navigationDirection = 1
    @Published var mainVisible = false
    @Published var onboardingStep = 0
    @Published var onboarded = UserDefaults.standard.bool(forKey: "onboarded")
    @Published var selectedID = UserDefaults.standard.string(forKey: "selectedID") ?? "" {
        didSet { UserDefaults.standard.set(selectedID, forKey: "selectedID"); updateFloating() }
    }
    @Published var mode = DisplayMode(rawValue: UserDefaults.standard.string(forKey: "displayMode") ?? "") ?? .whileIWork {
        didSet { UserDefaults.standard.set(mode.rawValue, forKey: "displayMode"); policy.mode = mode; policy.show(); updateFloating() }
    }
    @Published var plantSize = UserDefaults.standard.double(forKey: "plantSize") == 0 ? 180.0 : UserDefaults.standard.double(forKey: "plantSize") {
        didSet { UserDefaults.standard.set(plantSize, forKey: "plantSize") }
    }
    @Published var idleDelay = UserDefaults.standard.double(forKey: "idleDelay") == 0 ? 180.0 : UserDefaults.standard.double(forKey: "idleDelay") {
        didSet { UserDefaults.standard.set(idleDelay, forKey: "idleDelay"); policy.inactivityDelay = idleDelay; updateFloating() }
    }
    @Published var appearance = UserDefaults.standard.string(forKey: "appearance") ?? "system" {
        didSet { UserDefaults.standard.set(appearance, forKey: "appearance"); applyAppearance() }
    }
    @Published var corner = FloatingCorner(rawValue: UserDefaults.standard.string(forKey: "floatingCorner") ?? "") ?? .bottomRight {
        didSet {
            UserDefaults.standard.set(corner.rawValue, forKey: "floatingCorner")
            UserDefaults.standard.removeObject(forKey: "floatingX"); UserDefaults.standard.removeObject(forKey: "floatingY")
            NotificationCenter.default.post(name: .potResetPosition, object: nil)
        }
    }
    @Published private(set) var floatingVisible = false
    @Published private(set) var floatingManuallyHidden = false
    var openMain: (() -> Void)?
    private let queue = DispatchQueue(label: "app.pot.ingestion", qos: .utility)
    private let worker = GardenWorker()
    private var roots: [Provider: [URL]] = [:]
    private var observer: DirectoryObserver?
    private var timer: Timer?
    private var visibilityTimer: Timer?
    private var policy = FloatingPolicy(mode: .whileIWork)
    private var pendingScan = false
    var selected: AccountSnapshot? { snapshots.first { $0.profile.id == selectedID } ?? snapshots.first }
    var colorScheme: ColorScheme? { appearance == "dark" ? .dark : appearance == "light" ? .light : nil }
    var launchAtLogin: Bool { SMAppService.mainApp.status == .enabled }
    var canContinueDetection: Bool { detections.contains { enabledProviders.contains($0.provider) && ($0.executable != nil || !$0.roots.isEmpty) } || roots.contains { enabledProviders.contains($0.key) && !$0.value.isEmpty } }

    init() {
        policy = FloatingPolicy(mode: mode, inactivityDelay: idleDelay)
        applyAppearance()
        visibilityTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updateFloating() }
        }
    }

    private func applyAppearance() {
        NSApp.appearance = appearance == "dark" ? NSAppearance(named: .darkAqua) : appearance == "light" ? NSAppearance(named: .aqua) : nil
    }
    /// Account details come from the agents' own status commands (Codex: `app-server account/read`
    /// with refreshToken false). Pot never reads credentials; this is display-only.
    func refreshDetection(includeAccountDetails: Bool = true) {
        guard !busy else { return }
        busy = true; message = nil
        queue.async { [weak self] in
            let detected = SourceDiscovery.detect(includeAccountDetails: includeAccountDetails)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.detections = detected
                self.roots = Dictionary(uniqueKeysWithValues: detected.map { detection in
                    let custom = UserDefaults.standard.stringArray(forKey: "roots.\(detection.provider.rawValue)") ?? []
                    return (detection.provider, Array(Set(detection.roots + custom.map { URL(fileURLWithPath: $0) })))
                })
                self.busy = false
                self.observeRoots()
                if self.onboarded { self.scan() }
            }
        }
    }
    func chooseFolder(for provider: Provider) {
        let picker = NSOpenPanel()
        picker.canChooseDirectories = true; picker.canChooseFiles = false; picker.allowsMultipleSelection = false
        picker.prompt = "Use folder"; picker.message = "Choose the \(provider.displayName) folder containing local session logs. Pot keeps only usage metrics."
        guard picker.runModal() == .OK, let folder = picker.url else { return }
        var custom = UserDefaults.standard.stringArray(forKey: "roots.\(provider.rawValue)") ?? []
        if !custom.contains(folder.path) { custom.append(folder.path) }
        UserDefaults.standard.set(custom, forKey: "roots.\(provider.rawValue)")
        roots[provider, default: []].append(folder)
        enabledProviders.insert(provider)
        observeRoots()
        if onboarded { scan() }
        objectWillChange.send()
    }
    func setEnabled(_ provider: Provider, enabled: Bool) {
        if enabled { enabledProviders.insert(provider) } else { enabledProviders.remove(provider) }
        UserDefaults.standard.set(!enabled, forKey: "disabled.\(provider.rawValue)")
        observeRoots()
        if onboarded { scan() }
    }
    func finishOnboarding() {
        onboarded = true; UserDefaults.standard.set(true, forKey: "onboarded")
        scan(); observeRoots()
    }
    private func observeRoots() {
        observer = DirectoryObserver(roots: roots.filter { enabledProviders.contains($0.key) }.values.flatMap { $0 }) { [weak self] in
            DispatchQueue.main.async { self?.scheduleFileScan() }
        }
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.scan() }
        }
    }
    /// Agents append to their logs continuously while working. Coalesce file events so Pot
    /// rescans at most every few seconds instead of after every write.
    private var fileScanScheduled = false
    private var lastScanStarted = Date.distantPast
    private func scheduleFileScan() {
        guard !fileScanScheduled else { return }
        let wait = max(0, 4 - Date().timeIntervalSince(lastScanStarted))
        fileScanScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + wait) { [weak self] in
            guard let self else { return }
            self.fileScanScheduled = false
            self.scan()
        }
    }
    func scan() {
        guard onboarded else { return }
        guard !busy else { pendingScan = true; return }
        // Agents may create their first log directory after onboarding. Discover
        // newly available standard roots without repeatedly spawning status CLIs.
        var rootsChanged = false
        for provider in enabledProviders {
            let combined = Array(Set((roots[provider] ?? []) + SourceDiscovery.defaultRoots(provider: provider)))
            if Set(combined) != Set(roots[provider] ?? []) { roots[provider] = combined; rootsChanged = true }
        }
        if rootsChanged { observeRoots() }
        busy = true
        lastScanStarted = Date()
        let sources = roots.filter { enabledProviders.contains($0.key) }
        let agents = detections.filter { enabledProviders.contains($0.provider) }
        let worker = worker
        queue.async { [weak self] in
            let result = Result { try worker.scan(roots: sources, detections: agents, now: Date()) }
            let moreHistory = worker.pendingImport
            DispatchQueue.main.async {
                guard let self else { return }
                self.busy = false
                switch result {
                case .success(let snapshots):
                    self.snapshots = snapshots; self.message = nil
                    if !snapshots.contains(where: { $0.profile.id == self.selectedID }) { self.selectedID = snapshots.first?.profile.id ?? "" }
                case .failure:
                    self.message = "Pot could not safely update its local garden. Your existing plants are preserved. Check folder access and try again."
                }
                self.updateFloating()
                if self.pendingScan || moreHistory { self.pendingScan = false; self.scan() }
            }
        }
    }
    func exportGarden() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Pot garden \(Date().formatted(.iso8601.year().month().day())).json"
        panel.allowedContentTypes = [.json]
        panel.message = "Daily token totals, estimated API values and plant state. No conversations, paths or account identifiers."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let worker = worker
        queue.async { [weak self] in
            let result = Result { try worker.exportData(now: Date()).write(to: url, options: .atomic) }
            DispatchQueue.main.async {
                if case .failure = result { self?.message = "The export could not be written. Your garden is unchanged." }
            }
        }
    }
    func navigate(_ direction: Int) {
        guard !snapshots.isEmpty else { return }
        navigationDirection = direction < 0 ? -1 : 1
        let current = snapshots.firstIndex { $0.profile.id == selectedID } ?? 0
        selectedID = snapshots[(current + direction + snapshots.count) % snapshots.count].profile.id
    }
    func toggleFloating() {
        if floatingManuallyHidden || !floatingVisible {
            if mode == .menuBarOnly { mode = .alwaysWithMe }
            policy.show()
        } else { policy.hide() }
        updateFloating()
    }
    func hideFloating() { policy.hide(); updateFloating() }
    private func updateFloating() {
        // "While I work" follows any agent's activity, so switching to a quiet plant keeps it on screen.
        // Only the plant whose agent is working dances (PlantView `active`).
        floatingVisible = onboarded && policy.visible(lastActivity: snapshots.compactMap(\.lastActivity).max(), now: Date(), hasPlant: selected != nil)
        floatingManuallyHidden = policy.manuallyHidden
    }
    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            objectWillChange.send()
            if SMAppService.mainApp.status == .requiresApproval { message = "Allow Pot in System Settings → General → Login Items." }
        } catch { message = "Login items require Pot to be installed as an application. Check System Settings → General → Login Items." }
    }
    func eraseData() {
        busy = true; observer = nil; timer?.invalidate()
        let worker = worker
        queue.async { [weak self] in
            let result = Result { try worker.eraseAll() }
            DispatchQueue.main.async {
                guard let self else { return }
                self.busy = false
                if case .failure = result { self.message = "Local data could not be removed. Please try again."; return }
                for key in ["onboarded", "selectedID", "displayMode", "plantSize", "idleDelay", "appearance", "floatingX", "floatingY", "roots.codex", "roots.claude", "disabled.codex", "disabled.claude", "gardenPaused", "floatingCorner"] { UserDefaults.standard.removeObject(forKey: key) }
                self.snapshots = []; self.detections = []; self.roots = [:]; self.selectedID = ""
                self.onboarded = false; self.onboardingStep = 0; self.showSettings = false
                self.pendingScan = false; self.enabledProviders = Set(Provider.allCases)
                self.mode = .whileIWork; self.plantSize = 180; self.idleDelay = 180; self.appearance = "system"; self.corner = .bottomRight
                self.policy.show(); self.updateFloating()
            }
        }
    }
    func shutdown() { timer?.invalidate(); visibilityTimer?.invalidate(); observer = nil; queue.sync {} }
}

/// Recursive FSEvents wakes a serialized incremental scan. A 60s fallback covers missed events.
private final class DirectoryObserver {
    private var stream: FSEventStreamRef?
    private let callback: () -> Void
    private let queue = DispatchQueue(label: "app.pot.files", qos: .utility)
    init(roots: [URL], callback: @escaping () -> Void) {
        self.callback = callback
        guard !roots.isEmpty else { return }
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil)
        stream = FSEventStreamCreate(kCFAllocatorDefault, { _, info, _, _, _, _ in
            guard let info else { return }
            Unmanaged<DirectoryObserver>.fromOpaque(info).takeUnretainedValue().callback()
        }, &context, roots.map(\.path) as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 1.5,
        FSEventStreamCreateFlags(kFSEventStreamCreateFlagWatchRoot | kFSEventStreamCreateFlagFileEvents))
        if let stream { FSEventStreamSetDispatchQueue(stream, queue); FSEventStreamStart(stream) }
    }
    deinit { if let stream { FSEventStreamStop(stream); FSEventStreamInvalidate(stream); FSEventStreamRelease(stream) } }
}
#endif
