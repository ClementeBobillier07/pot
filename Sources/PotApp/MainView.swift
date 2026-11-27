#if os(macOS)
import AppKit
import SwiftUI
import Charts
import PotCore

/// Brand green; lighter in dark mode so "Today", the selected day and page dots keep contrast.
private let forest = Color(nsColor: NSColor(name: nil) { appearance in
    appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        ? NSColor(red: 0.55, green: 0.76, blue: 0.56, alpha: 1)
        : NSColor(red: 0.22, green: 0.36, blue: 0.28, alpha: 1)
})

struct MainView: View {
    @ObservedObject var model: AppModel
    /// One unit for the headline and the weekly chart; remembered between launches.
    @AppStorage("showUSD") private var dollars = false
    @State private var selectedDate: Date?
    @State private var period: UsagePeriod = .today
    /// 0 = this week, 1 = last week, …
    @State private var weekOffset = 0
    /// Chart selection by day key (yyyy-MM-dd); categorical so all seven labels always show.
    @State private var selectedKey: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("pot").font(.system(size: 23, weight: .semibold, design: .serif))
                Spacer()
                if model.busy { ProgressView().controlSize(.small).accessibilityLabel("Refreshing local garden") }
                if model.onboarded && !model.showSettings && !model.snapshots.isEmpty {
                    Button { withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) { model.showGrid.toggle() } } label: {
                        Image(systemName: model.showGrid ? "rectangle.portrait" : "square.grid.2x2")
                    }
                    .buttonStyle(.plain).padding(.trailing, 14)
                    .help(model.showGrid ? "Show one plant" : "See your whole garden")
                    .accessibilityLabel(model.showGrid ? "Show one plant" : "See your whole garden")
                    .keyboardShortcut("g", modifiers: .command)
                }
                Button { model.showSettings.toggle() } label: { Image(systemName: model.showSettings ? "xmark" : "slider.horizontal.3") }
                    .buttonStyle(.plain).accessibilityLabel(model.showSettings ? "Close settings" : "Settings")
            }.padding(.horizontal, 26).padding(.vertical, 18)
            if model.showSettings {
                SettingsView(model: model)
            } else if !model.onboarded {
                OnboardingView(model: model)
            } else if model.showGrid, !model.snapshots.isEmpty {
                GardenGrid(model: model)
                    .transition(reduceMotion ? .identity : .opacity.combined(with: .scale(scale: 0.97)))
            } else if let account = model.selected {
                accountView(account)
                    .transition(reduceMotion ? .identity : .opacity)
            } else {
                VStack(spacing: 18) {
                    Spacer()
                    Image(systemName: "leaf").font(.system(size: 44)).foregroundStyle(forest)
                    Text("A little room to grow.").font(.title2)
                    Text("Use Codex or Claude Code, then refresh your local sources.").multilineTextAlignment(.center).foregroundStyle(.secondary)
                    Button("Refresh detection") { model.refreshDetection() }.disabled(model.busy)
                    Button("Choose a log folder…") { model.showSettings = true }
                    Spacer()
                }.padding(32)
            }
            if let message = model.message {
                Text(message).font(.callout).foregroundStyle(.secondary).padding(16).accessibilityAddTraits(.updatesFrequently)
            }
        }
        .frame(minWidth: 420, idealWidth: 430, maxWidth: .infinity, minHeight: 700, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .tint(forest)
        .preferredColorScheme(model.colorScheme)
        .background(TrackpadNavigation {
            if model.onboarded && !model.showSettings && !model.showGrid { navigate($0) }
        })
        .onChange(of: model.selectedID) { _, _ in selectedDate = nil; selectedKey = nil; weekOffset = 0 }
        .onMoveCommand { direction in
            guard model.onboarded, !model.showSettings else { return }
            guard !model.showGrid else { return }
            if direction == .left { navigate(-1) }
            if direction == .right { navigate(1) }
        }
    }

    private func navigate(_ direction: Int) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.28)) { model.navigate(direction) }
        selectedDate = nil
    }
    private func navButton(_ direction: Int) -> some View {
        let many = model.snapshots.count > 1
        return Button { navigate(direction) } label: {
            Image(systemName: direction < 0 ? "chevron.left" : "chevron.right")
                .font(.system(size: 15, weight: .medium)).frame(width: 32, height: 32).contentShape(Rectangle())
        }
        .buttonStyle(.plain).foregroundStyle(.secondary)
        .opacity(many ? 1 : 0).disabled(!many)
        .accessibilityLabel(direction < 0 ? "Previous plant" : "Next plant")
    }

    private func accountView(_ account: AccountSnapshot) -> some View {
        let week = account.weeks.indices.contains(weekOffset) ? account.weeks[weekOffset] : account.days
        let today = Calendar.current.startOfDay(for: Date())
        let selected = selectedDate.flatMap { date in week.first { Calendar.current.isDate($0.date, inSameDayAs: date) && $0.date <= today } }
        let summary = account.periods[period]
        let headlineTokens = selected?.tokens ?? summary?.tokens
        let headlineUSD = selected.map { $0.estimatedUSD } ?? summary?.estimatedUSD
        let headlinePartial = selected?.partial ?? summary?.partial ?? false
        let usd: Decimal? = headlineUSD ?? nil
        // The unit toggle drives the big number too, so the headline and the chart always agree.
        let headline: String = {
            guard let tokens = headlineTokens else { return "…" }
            return dollars ? usd.map { money($0) } ?? "—" : tokens.formatted()
        }()
        let noun = dollars ? (usd == nil && headlineTokens != nil ? "no verified rate" : "estimated USD") : "tokens"
        let caption = selected.map { "\(noun) · " + $0.date.formatted(.dateTime.month(.abbreviated).day()) } ?? periodCaption(account, noun: noun)
        // Fixed composition: the plant has a stage with room to grow upward (the whole canvas,
        // bottom-aligned on the stats), and the statistics stay anchored at the bottom, so nothing
        // moves as the plant grows from seedling to full.
        return VStack(spacing: 0) {
            HStack(spacing: 10) {
                navButton(-1)
                VStack(spacing: 3) {
                    Text(account.profile.provider.displayName).font(.system(size: 24, weight: .medium, design: .serif))
                    Text(account.profile.email ?? account.profile.alias).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                }.frame(minWidth: 220)
                navButton(1)
            }
            if model.snapshots.count > 1 {
                // Page dots: where this plant sits in the garden.
                HStack(spacing: 7) {
                    ForEach(model.snapshots, id: \.profile.id) { snap in
                        Circle().fill(snap.profile.id == account.profile.id ? forest : Color.secondary.opacity(0.3))
                            .frame(width: 6, height: 6)
                    }
                }
                .padding(.top, 10)
                .accessibilityElement().accessibilityLabel("Plant \((model.snapshots.firstIndex { $0.profile.id == account.profile.id } ?? 0) + 1) of \(model.snapshots.count)")
            }
            PlantView(plant: account.plant, active: model.mainVisible && isActive(account), idle: model.mainVisible)
                .frame(maxWidth: .infinity, minHeight: 220, maxHeight: .infinity)
                .id(account.profile.id)
                .transition(reduceMotion ? .opacity : PlantSwitch.transition(direction: model.navigationDirection))
                .padding(.top, 8)
            Text(PlantStatus.describe(account.plant, lastActivity: account.lastActivity))
                .font(.caption).foregroundStyle(.secondary).padding(.top, 6)

            VStack(spacing: 4) {
                Picker("Period", selection: $period) {
                    ForEach(UsagePeriod.allCases) { Text($0.title).tag($0) }
                }.pickerStyle(.segmented).labelsHidden().frame(width: 290).padding(.bottom, 6)
                .onChange(of: period) { _, _ in selectedDate = nil }
                Text(headline)
                    .font(.system(size: 30, weight: .light, design: .rounded)).monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: dollars)
                Text(caption + (dollars && headlinePartial && usd != nil ? " · partial" : ""))
                    .font(.callout).foregroundStyle(.secondary)
                HStack(spacing: 5) {
                    if dollars {
                        // The other unit stays one line below, so nothing is lost when switching.
                        Text(headlineTokens.map { "\($0.formatted()) tokens" } ?? "…")
                    } else {
                        Text(headlineTokens == nil ? "…" : money(usd))
                        Text("Estimated API value\(headlinePartial ? " · partial" : "")")
                    }
                }.font(.caption).foregroundStyle(.secondary).padding(.top, 2).monospacedDigit()
                .help("Reference API prices for the same tokens. Not your bill or subscription usage.")
            }.padding(.top, 18)
            VStack(spacing: 10) {
                HStack(spacing: 6) {
                    Button { weekOffset += 1; selectedDate = nil; selectedKey = nil } label: { Image(systemName: "chevron.left") }
                        .buttonStyle(.plain).foregroundStyle(.secondary).disabled(weekOffset >= account.weeks.count - 1)
                        .accessibilityLabel("Previous week")
                    Text(weekTitle(week)).font(.callout).monospacedDigit().frame(minWidth: 112)
                    Button { weekOffset -= 1; selectedDate = nil; selectedKey = nil } label: { Image(systemName: "chevron.right") }
                        .buttonStyle(.plain).foregroundStyle(.secondary).disabled(weekOffset == 0)
                        .accessibilityLabel("Next week")
                    Spacer()
                    Picker("Unit", selection: $dollars) {
                        Text("Tokens").tag(false); Text("USD").tag(true)
                    }.pickerStyle(.segmented).labelsHidden().frame(width: 132)
                }
                let peak = max(1, week.map(chartValue).max() ?? 1)
                Chart(week, id: \.date) { day in
                    let key = Self.dayKey(day.date)
                    let isToday = Calendar.current.isDate(day.date, inSameDayAs: today)
                    let isFuture = day.date > today
                    let isSelected = selectedKey == key
                    // Future days keep a faint slot so the week reads Monday to Sunday.
                    BarMark(x: .value("Day", key), y: .value(dollars ? "Estimated USD" : "Tokens", isFuture ? peak * 0.025 : chartValue(day)), width: .ratio(0.55))
                        .foregroundStyle(isFuture ? Color.secondary.opacity(0.12) : (isToday || isSelected) ? forest : forest.opacity(0.35))
                        .cornerRadius(3)
                        .annotation(position: .top, spacing: 3) {
                            if isToday { Text("Today").font(.caption2.weight(.semibold)).foregroundStyle(forest) }
                        }
                        .accessibilityLabel((isToday ? "Today, " : "") + day.date.formatted(.dateTime.weekday(.wide).month().day()))
                        .accessibilityValue(isFuture ? "Not yet" : dollars ? money(day.estimatedUSD) + (day.partial ? ", partial estimate" : "") : "\(day.tokens.formatted()) tokens")
                }
                .chartXSelection(value: $selectedKey)
                .onChange(of: selectedKey) { _, key in selectedDate = key.flatMap { k in week.first { Self.dayKey($0.date) == k }?.date } }
                .chartYAxis(.hidden)
                .chartXAxis {
                    AxisMarks(values: week.map { Self.dayKey($0.date) }) { value in
                        let date = value.as(String.self).flatMap { k in week.first { Self.dayKey($0.date) == k }?.date }
                        let isToday = date.map { Calendar.current.isDate($0, inSameDayAs: today) } ?? false
                        AxisValueLabel {
                            Text(date?.formatted(.dateTime.weekday(.narrow)) ?? "")
                                .fontWeight(isToday ? .bold : .regular)
                                .foregroundStyle(isToday ? forest : Color.secondary)
                        }
                    }
                }
                .chartYScale(domain: 0...(peak * 1.18))
                .frame(height: 84)
                HStack {
                    Text(weekOffset == 0 ? "Week so far" : "Week total")
                    Spacer()
                    Text(dollars ? weeklyMoney(week.filter { $0.date <= today }) : "\(weeklyTokens(week).formatted()) tokens")
                }.font(.caption).foregroundStyle(.secondary)
                if dollars && week.contains(where: { $0.date <= today && ($0.partial || $0.estimatedUSD == nil) }) {
                    Text("Some models or billing categories have no verified rate. Empty bars may have unavailable values.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }.padding(.horizontal, 32).padding(.top, 18)
            VStack(spacing: 2) {
                Text(account.coverage)
                Text("\(coverageLine(account)) · rates \(account.priceReference)")
            }
            .font(.caption2).foregroundStyle(.tertiary).multilineTextAlignment(.center)
            .padding(.horizontal, 24).padding(.top, 14).padding(.bottom, 16)
        }
    }
    private static let keyFormatter: DateFormatter = {
        let f = DateFormatter(); f.calendar = Calendar(identifier: .gregorian); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"; return f
    }()
    static func dayKey(_ date: Date) -> String { keyFormatter.string(from: date) }
    private func weekTitle(_ week: [DailyUsage]) -> String {
        switch weekOffset {
        case 0: return "This week"
        case 1: return "Last week"
        default:
            guard let first = week.first?.date, let last = week.last?.date else { return "" }
            return "\(first.formatted(.dateTime.month(.abbreviated).day())) – \(last.formatted(.dateTime.day()))"
        }
    }
    private func periodCaption(_ account: AccountSnapshot, noun: String) -> String {
        switch period {
        case .today: return "\(noun) today"
        case .week: return "\(noun) · last 7 days"
        case .month: return "\(noun) · last 30 days"
        case .all: return account.historyStart.map { "\(noun) · since " + $0.formatted(.dateTime.month(.abbreviated).day().year()) } ?? "\(noun) · all local history"
        }
    }
    private func coverageLine(_ account: AccountSnapshot) -> String {
        let since = account.historyStart.map { "Data since " + $0.formatted(.dateTime.month(.abbreviated).day().year()) } ?? "No records yet"
        return "\(since) · \(account.recordCount.formatted()) calls · read \(account.lastRead.formatted(date: .omitted, time: .shortened))"
    }
    private func chartValue(_ day: DailyUsage) -> Double {
        dollars ? day.estimatedUSD.map { NSDecimalNumber(decimal: $0).doubleValue } ?? 0 : Double(day.tokens)
    }
    private func isActive(_ snapshot: AccountSnapshot) -> Bool {
        snapshot.lastActivity.map { Date().timeIntervalSince($0) >= 0 && Date().timeIntervalSince($0) < 90 } ?? false
    }
    private func money(_ value: Decimal?) -> String {
        guard let value else { return "Unavailable" }
        return value.formatted(.currency(code: "USD").precision(.fractionLength(2)))
    }
    private func weeklyMoney(_ days: [DailyUsage]) -> String {
        guard days.contains(where: { $0.estimatedUSD != nil }) else { return "Unavailable" }
        return money(days.reduce(Decimal(0)) { $0 + ($1.estimatedUSD ?? 0) }) + (days.contains { $0.partial || $0.estimatedUSD == nil } ? " · partial" : "")
    }
    private func weeklyTokens(_ days: [DailyUsage]) -> Int64 {
        days.reduce(Int64(0)) { sum, day in
            let (next, overflow) = sum.addingReportingOverflow(day.tokens)
            return overflow ? Int64.max : next
        }
    }
}

private struct OnboardingView: View {
    @ObservedObject var model: AppModel
    /// Illustration only (not anyone's data): a fully grown variation-01 Codex plant.
    static let illustration: PlantState = {
        var seed: UInt64 = 17
        while PlantSpecies.of(seed: seed) != .classic { seed += 1 }
        var plant = PlantState(seed: seed, provider: .codex, createdAt: Date(timeIntervalSince1970: 0))
        plant.growth = PlantFormBuilder.daysToFull
        return plant
    }()
    var body: some View {
        ScrollView {
        VStack(spacing: 22) {
            Spacer(minLength: 10)
            switch model.onboardingStep {
            case 0:
                PlantView(plant: Self.illustration).frame(height: 240)
                    .accessibilityHint("An illustration of what a plant can grow into")
                Text("A little plant on your Mac.").font(.system(size: 28, weight: .regular, design: .serif)).multilineTextAlignment(.center)
                Text("You code. It grows.").foregroundStyle(.secondary)
                Text("Pot reads local Codex and Claude Code records. It keeps usage counts and your garden, never your conversations or code. No Pot account. No telemetry.")
                    .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Button("Plant your first seed") { model.onboardingStep = 1; model.refreshDetection() }.buttonStyle(.borderedProminent)
            case 1, 2:
                Text(model.onboardingStep == 1 ? "A familiar place to start." : "Meet your local garden.")
                    .font(.system(size: 28, design: .serif)).multilineTextAlignment(.center)
                Text(model.onboardingStep == 1 ? "Find the agents you already use. You stay signed in with them." : "Current sign-in does not identify old records. History without account evidence gets its own local plant.")
                    .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                ForEach(Provider.allCases, id: \.rawValue) { provider in
                    let detection = model.detections.first { $0.provider == provider }
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle(provider.displayName, isOn: Binding(get: { model.enabledProviders.contains(provider) }, set: { model.setEnabled(provider, enabled: $0) }))
                        Text(detection?.status ?? "Searching local sources…").font(.callout).foregroundStyle(.secondary)
                        if let email = detection?.account?.email { Text(email).font(.callout) }
                        if let authenticated = detection?.authenticated {
                            Text(authenticated ? "Already signed in" : "Sign in within \(provider.displayName) when you are ready").font(.caption).foregroundStyle(.secondary)
                        }
                        Button("Choose log folder…") { model.chooseFolder(for: provider) }.buttonStyle(.link)
                    }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 16))
                }
                HStack {
                    Button("Search again") { model.refreshDetection() }.disabled(model.busy)
                    Button("Continue") { model.onboardingStep += 1 }.buttonStyle(.borderedProminent).disabled(model.busy || !model.canContinueDetection)
                }
            case 3:
                Text("A little company?").font(.system(size: 30, design: .serif))
                Text("Choose where Pot feels at home. You can change this any time.").foregroundStyle(.secondary).multilineTextAlignment(.center)
                ForEach(DisplayMode.allCases, id: \.rawValue) { mode in
                    Button { model.mode = mode } label: {
                        HStack(spacing: 15) {
                            Image(systemName: mode == .menuBarOnly ? "menubar.rectangle" : mode == .whileIWork ? "sun.max" : "leaf")
                            VStack(alignment: .leading, spacing: 5) {
                                Text(mode.title).font(.headline)
                                Text(mode == .menuBarOnly ? "Quietly tucked into your menu bar." : mode == .whileIWork ? "A companion when your agents are active." : "A small presence on your desktop.")
                                    .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.leading)
                            }
                            Spacer(minLength: 0)
                            if model.mode == mode { Image(systemName: "checkmark.circle.fill") }
                        }.padding(16).frame(maxWidth: .infinity).background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 16))
                    }.buttonStyle(.plain)
                }
                if model.mode != .menuBarOnly {
                    VStack(spacing: 8) {
                        Text("Which corner?").font(.headline)
                        CornerPicker(selection: $model.corner)
                    }.padding(.top, 4)
                }
                Button("Make yourself at home") { model.onboardingStep = 4 }.buttonStyle(.borderedProminent)
            default:
                Image(systemName: "leaf.fill").font(.system(size: 50)).foregroundStyle(forest)
                Text("Let something grow.").font(.system(size: 30, design: .serif))
                Text("Your first plant starts as a seedling and grows a little with every day of work. A day off changes nothing; longer breaks show, and it always comes back.")
                    .foregroundStyle(.secondary).multilineTextAlignment(.center)
                Button("Open my garden") { model.finishOnboarding() }.buttonStyle(.borderedProminent)
            }
            Spacer(minLength: 10)
            if model.onboardingStep > 0 { Button("Back") { model.onboardingStep -= 1 }.buttonStyle(.plain).foregroundStyle(.secondary) }
        }.frame(maxWidth: .infinity).padding(30)
        }
    }
}

private struct SettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var updates = UpdateController.shared
    @State private var confirmErase = false
    var body: some View {
        Form {
            Section("Connected agents") {
                ForEach(Provider.allCases, id: \.rawValue) { provider in
                    let detection = model.detections.first { $0.provider == provider }
                    VStack(alignment: .leading, spacing: 6) {
                        Toggle(provider.displayName, isOn: Binding(get: { model.enabledProviders.contains(provider) }, set: { model.setEnabled(provider, enabled: $0) }))
                        AccountLine(detection: detection, provider: provider, searching: model.busy && model.detections.isEmpty)
                        Text([detection?.status ?? "Refresh to find local sources", detection?.version].compactMap { $0 }.joined(separator: " · "))
                            .font(.caption).foregroundStyle(.secondary)
                        Button("Choose log folder…") { model.chooseFolder(for: provider) }
                    }.padding(.vertical, 4)
                }
                Button("Refresh") { model.refreshDetection() }.disabled(model.busy)
                Text("Accounts come from each agent’s own status command. Pot never reads credentials or signs in for you. This is who is signed in now; past activity is only linked to an account when the logs say so.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("At home on your Mac") {
                Picker("Display mode", selection: $model.mode) { ForEach(DisplayMode.allCases, id: \.rawValue) { Text($0.title).tag($0) } }
                Picker("Corner", selection: $model.corner) { ForEach(FloatingCorner.allCases, id: \.rawValue) { Text($0.title).tag($0) } }
                    .disabled(model.mode == .menuBarOnly)
                Slider(value: $model.plantSize, in: 130...280, step: 10) { Text("Floating plant size") }
                Button("Reset floating position") {
                    UserDefaults.standard.removeObject(forKey: "floatingX"); UserDefaults.standard.removeObject(forKey: "floatingY")
                    NotificationCenter.default.post(name: .potResetPosition, object: nil)
                }
                Picker("Hide after inactivity", selection: $model.idleDelay) {
                    Text("1 minute").tag(60.0); Text("3 minutes").tag(180.0); Text("5 minutes").tag(300.0); Text("10 minutes").tag(600.0)
                }
                Toggle("Launch at login", isOn: Binding(get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) }))
                Picker("Appearance", selection: $model.appearance) { Text("System").tag("system"); Text("Light").tag("light"); Text("Dark").tag("dark") }
            }
            Section("Updates") {
                Toggle("Update Pot automatically", isOn: Binding(get: { updates.automatic }, set: { updates.setAutomatic($0) }))
                    .disabled(!updates.available)
                if !updates.available {
                    Text("Updates work in the installed app.").font(.caption).foregroundStyle(.secondary)
                } else if updates.automatic {
                    Text("Pot checks once a day and installs new versions on its own, after you close this window. It only sends its version number; your usage never leaves this Mac.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Button("Check for updates…") { updates.checkNow() }.disabled(!updates.canCheck)
                    Text("Pot never checks on its own. Press the button to look for a new version.").font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("About Pot") {
                Text("Pot \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "development build") · A little plant on your Mac.")
                Text("Usage and plants stay on this Mac. Records may contain conversations; Pot keeps only usage metrics. Prices are bundled reference rates, not your bill. Unknown models remain unpriced.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Export garden and daily totals…") { model.exportGarden() }.disabled(model.busy || model.snapshots.isEmpty)
                Text("Saves a JSON file you control: daily token totals, estimated values and plant state. No conversations, paths or account identifiers.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Delete local data and plants…", role: .destructive) { confirmErase = true }.disabled(model.busy)
                Button("Quit Pot") { NSApp.terminate(nil) }
            }
        }.formStyle(.grouped)
        .confirmationDialog("Delete your local garden?", isPresented: $confirmErase, titleVisibility: .visible) {
            Button("Delete all Pot data", role: .destructive) { model.eraseData() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("This removes Pot’s usage history, plants and preferences. Agent logs are untouched. Reimporting logs starts a new garden; records already removed by your agents cannot be recovered.") }
    }
}

/// One calm line about the plant: how it's growing, or how long it has been without work.
/// The variant is never named (owner, 2026-11-26): people discover what their seed becomes.
enum PlantStatus {
    static func describe(_ plant: PlantState, lastActivity: Date?, now: Date = Date()) -> String {
        let idleDays = lastActivity.map { max(0, now.timeIntervalSince($0) / 86400) } ?? 0
        if plant.health < 0.97 {
            if idleDays < 1 { return "Recovering" }
            let days = Int(idleDays)
            let away = days == 1 ? "1 day without work" : "\(days) days without work"
            if plant.health > 0.75 { return "A little thirsty · \(away)" }
            if plant.health > 0.4 { return "Wilting · \(away)" }
            return "Dry · a week of work brings it back"
        }
        let form = PlantFormBuilder.build(plant)
        let stage: String
        switch form.growth {
        case ..<0.04: stage = "A new seedling"
        case ..<0.3: stage = "Growing"
        case ..<1: stage = form.flowers.contains { $0.openness >= 0.6 } ? "In bloom" : "Budding"
        default: stage = "Fully grown"
        }
        return stage
    }
}

/// Who is signed in to an agent right now, from its own status command.
private struct AccountLine: View {
    let detection: AgentDetection?
    let provider: Provider
    var searching = false
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: icon).foregroundStyle(tint).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout).textSelection(.enabled)
                if let detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
            }
        }
    }
    private var account: DetectedAccount? { detection?.account }
    private var icon: String {
        switch detection?.authenticated { case true?: return "person.crop.circle.badge.checkmark"; case false?: return "person.crop.circle.badge.xmark"; default: return "person.crop.circle.badge.questionmark" }
    }
    private var tint: Color { detection?.authenticated == true ? forest : .secondary }
    private var title: String {
        if searching { return "Checking…" }
        guard let detection else { return "Not checked yet" }
        if detection.executable == nil { return "\(provider.displayName) isn’t installed on this Mac" }
        switch detection.authenticated {
        case true?: return account?.email ?? "Signed in"
        case false?: return "Not signed in · sign in within \(provider.displayName)"
        default: return "Sign-in status unknown"
        }
    }
    private var detail: String? {
        guard detection?.authenticated == true, let account else { return nil }
        // Personal organizations are named after the email; only show a distinct team/workspace name.
        let organization = account.organization.flatMap { org in account.email.map { org.contains($0) } == true ? nil : org }
        let parts = [account.method.map { "via \($0)" }, account.plan.map { $0.prefix(1).uppercased() + $0.dropFirst() + " plan" }, organization]
        let text = parts.compactMap { $0 }.joined(separator: " · ")
        return text.isEmpty ? nil : text
    }
}

/// Every plant at once, small and gently swaying, in garden order. Click one to open it.
private struct GardenGrid: View {
    @ObservedObject var model: AppModel
    @State private var hovered: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 165, maximum: 240), spacing: 16)], spacing: 16) {
                ForEach(model.snapshots, id: \.profile.id) { snap in
                    let isSelected = snap.profile.id == model.selected?.profile.id
                    Button {
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) {
                            model.selectedID = snap.profile.id
                            model.showGrid = false
                        }
                    } label: {
                        VStack(spacing: 4) {
                            // Same fixed stage as the window: room to grow upward, pots aligned across cards.
                            PlantView(plant: snap.plant, active: model.mainVisible && recentlyActive(snap), idle: model.mainVisible)
                                .frame(width: 140, height: 175)
                            Text(snap.profile.provider.displayName).font(.system(size: 17, weight: .medium, design: .serif))
                            Text(snap.profile.alias).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            Text("\((snap.periods[.today]?.tokens ?? 0).formatted(.number.notation(.compactName))) tokens today")
                                .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                        }
                        .padding(.vertical, 12).padding(.horizontal, 8)
                        .frame(maxWidth: .infinity)
                        .background(RoundedRectangle(cornerRadius: 18).fill(Color.primary.opacity(isSelected ? 0.07 : hovered == snap.profile.id ? 0.05 : 0.025)))
                        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(isSelected ? forest.opacity(0.45) : .clear, lineWidth: 1.2))
                        .contentShape(RoundedRectangle(cornerRadius: 18))
                        .scaleEffect(hovered == snap.profile.id && !reduceMotion ? 1.02 : 1)
                    }
                    .buttonStyle(.plain)
                    .onHover { inside in withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) { hovered = inside ? snap.profile.id : (hovered == snap.profile.id ? nil : hovered) } }
                    .accessibilityLabel("\(snap.profile.provider.displayName), \(snap.profile.alias)")
                    .accessibilityHint("Opens this plant")
                }
            }
            .padding(.horizontal, 22).padding(.top, 4)
            Text(model.snapshots.count == 1 ? "1 plant" : "\(model.snapshots.count) plants")
                .font(.caption).foregroundStyle(.secondary).padding(.vertical, 18)
        }
    }
    private func recentlyActive(_ snap: AccountSnapshot) -> Bool {
        snap.lastActivity.map { Date().timeIntervalSince($0) >= 0 && Date().timeIntervalSince($0) < 90 } ?? false
    }
}

/// Four tappable corners of a miniature screen; bottom right is the suggested default.
private struct CornerPicker: View {
    @Binding var selection: FloatingCorner
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10).fill(.quaternary.opacity(0.35))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.quaternary))
            VStack {
                HStack { cell(.topLeft); Spacer(); cell(.topRight) }
                Spacer()
                HStack { cell(.bottomLeft); Spacer(); cell(.bottomRight) }
            }.padding(8)
        }.frame(width: 190, height: 118)
    }
    private func cell(_ corner: FloatingCorner) -> some View {
        Button { selection = corner } label: {
            Image(systemName: selection == corner ? "leaf.circle.fill" : "circle.dashed")
                .font(.system(size: 22)).frame(width: 34, height: 34).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel(corner.title).accessibilityAddTraits(selection == corner ? .isSelected : [])
    }
}

/// Trackpad horizontal scrolling is navigation, with a threshold and momentum debounce.
private struct TrackpadNavigation: NSViewRepresentable {
    var navigate: (Int) -> Void
    func makeNSView(context: Context) -> ScrollNavigationView { ScrollNavigationView(navigate: navigate) }
    func updateNSView(_ view: ScrollNavigationView, context: Context) { view.navigate = navigate }
}
private final class ScrollNavigationView: NSView {
    var navigate: (Int) -> Void
    private var monitor: Any?
    private let gate = SwipeGate()
    init(navigate: @escaping (Int) -> Void) {
        self.navigate = navigate; super.init(frame: .zero)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self, event.window === self.window else { return event }
            if let direction = MainActor.assumeIsolated({ self.gate.direction(for: event, threshold: 65) }) { self.navigate(direction) }
            return event
        }
    }
    required init?(coder: NSCoder) { nil }
    deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
#endif
