#if os(macOS)
import AppKit
import SwiftUI
import Charts
import PotCore

private let forest = Color(red: 0.22, green: 0.36, blue: 0.28)

struct MainView: View {
    @ObservedObject var model: AppModel
    @State private var dollars = false
    @State private var selectedDate: Date?
    @State private var period: UsagePeriod = .today
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
        .frame(minWidth: 420, idealWidth: 430, maxWidth: .infinity, minHeight: 650, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .tint(forest)
        .preferredColorScheme(model.colorScheme)
        .background(TrackpadNavigation {
            if model.onboarded && !model.showSettings && !model.showGrid { navigate($0) }
        })
        .onChange(of: model.selectedID) { _, _ in selectedDate = nil }
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
        let selected = selectedDate.flatMap { date in account.days.first { Calendar.current.isDate($0.date, inSameDayAs: date) } }
        let summary = account.periods[period]
        let headlineTokens = selected?.tokens ?? summary?.tokens
        let headlineUSD = selected.map { $0.estimatedUSD } ?? summary?.estimatedUSD
        let headlinePartial = selected?.partial ?? summary?.partial ?? false
        return ScrollView {
            VStack(spacing: 5) {
                HStack(spacing: 10) {
                    navButton(-1)
                    VStack(spacing: 3) {
                        Text(account.profile.provider.displayName).font(.system(size: 24, weight: .medium, design: .serif))
                        Text(account.profile.email ?? account.profile.alias).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                    }.frame(minWidth: 220)
                    navButton(1)
                }
                PlantView(plant: account.plant, active: model.mainVisible && isActive(account), idle: model.mainVisible).frame(width: 290, height: 300)
                    .id(account.profile.id)
                    .transition(reduceMotion ? .identity : .opacity.combined(with: .scale(scale: 0.96, anchor: .bottom)))
                    .padding(.top, -6).padding(.bottom, 4)
                if account.paused {
                    Label("Garden paused · growth and wilting are on hold", systemImage: "pause.circle")
                        .font(.caption).foregroundStyle(.secondary).padding(.bottom, 4)
                }
                Picker("Period", selection: $period) {
                    ForEach(UsagePeriod.allCases) { Text($0.title).tag($0) }
                }.pickerStyle(.segmented).labelsHidden().frame(width: 290).padding(.bottom, 6)
                .onChange(of: period) { _, _ in selectedDate = nil }
                Text(headlineTokens.map { $0.formatted() } ?? "…")
                    .font(.system(size: 32, weight: .light, design: .rounded)).monospacedDigit()
                    .contentTransition(.numericText())
                Text(selected.map { "tokens · " + $0.date.formatted(.dateTime.month(.abbreviated).day()) } ?? periodCaption(account))
                    .font(.callout).foregroundStyle(.secondary)
                HStack(spacing: 5) {
                    Text(headlineTokens == nil ? "…" : money(headlineUSD ?? nil))
                    Text("Estimated API value\(headlinePartial ? " · partial" : "")")
                }.font(.caption).foregroundStyle(.secondary).padding(.top, 3)
                .help("Reference API prices for the same tokens. Not your bill or subscription usage.")
                VStack(spacing: 12) {
                    HStack {
                        Text("Last 7 days").font(.callout)
                        Spacer()
                        Picker("Chart unit", selection: $dollars) {
                            Text("Tokens").tag(false); Text("USD").tag(true)
                        }.pickerStyle(.segmented).labelsHidden().frame(width: 132)
                    }
                    Chart(account.days, id: \.date) { day in
                        BarMark(x: .value("Day", day.date, unit: .day), y: .value(dollars ? "Estimated USD" : "Tokens", chartValue(day)), width: .ratio(0.55))
                            .foregroundStyle(selectedDate.map { Calendar.current.isDate($0, inSameDayAs: day.date) } == true ? forest : forest.opacity(0.45))
                            .cornerRadius(3)
                            .accessibilityLabel(day.date.formatted(.dateTime.weekday(.wide).month().day()))
                            .accessibilityValue(dollars ? money(day.estimatedUSD) + (day.partial ? ", partial estimate" : "") : "\(day.tokens.formatted()) tokens")
                    }
                    .chartXSelection(value: $selectedDate)
                    .chartYAxis(.hidden)
                    .chartXAxis { AxisMarks(values: .stride(by: .day)) { value in AxisValueLabel(format: .dateTime.weekday(.narrow), centered: true) } }
                    .chartYScale(domain: 0...max(1, (account.days.map(chartValue).max() ?? 1) * 1.1))
                    .frame(height: 90)
                    HStack {
                        Text("Week total")
                        Spacer()
                        Text(dollars ? weeklyMoney(account.days) : "\(weeklyTokens(account.days).formatted()) tokens")
                    }.font(.caption).foregroundStyle(.secondary)
                    if dollars && account.days.contains(where: { $0.partial || $0.estimatedUSD == nil }) {
                        Text("Some models or billing categories have no verified rate. Empty bars may have unavailable values.")
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }.padding(.horizontal, 32).padding(.top, 22)
                if model.snapshots.count > 1 {
                    // Page dots: where this plant sits in the garden.
                    HStack(spacing: 7) {
                        ForEach(model.snapshots, id: \.profile.id) { snap in
                            Circle().fill(snap.profile.id == account.profile.id ? forest : Color.secondary.opacity(0.3))
                                .frame(width: 6, height: 6)
                        }
                    }
                    .padding(.top, 25).padding(.bottom, 12)
                    .accessibilityElement().accessibilityLabel("Plant \((model.snapshots.firstIndex { $0.profile.id == account.profile.id } ?? 0) + 1) of \(model.snapshots.count)")
                } else {
                    Spacer().frame(height: 20)
                }
                if Date().timeIntervalSince(account.plant.createdAt) < 3 * 86400 {
                    Text("Getting to know your rhythm · day \(min(3, max(1, Int(Date().timeIntervalSince(account.plant.createdAt) / 86400) + 1))) of 3")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text(account.coverage).font(.caption).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).padding(.horizontal, 30)
                Text(coverageLine(account)).font(.caption).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).padding(.horizontal, 30)
                Text("Reference API rates · \(account.priceReference)")
                    .font(.caption).foregroundStyle(.secondary).padding(.bottom, 20)
            }
        }
    }
    private func periodCaption(_ account: AccountSnapshot) -> String {
        switch period {
        case .today: return "tokens today"
        case .week: return "tokens · last 7 days"
        case .month: return "tokens · last 30 days"
        case .all: return account.historyStart.map { "tokens · since " + $0.formatted(.dateTime.month(.abbreviated).day().year()) } ?? "tokens · all local history"
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
    var body: some View {
        ScrollView {
        VStack(spacing: 22) {
            Spacer(minLength: 10)
            switch model.onboardingStep {
            case 0:
                PlantView(plant: PlantState(seed: 17, provider: .codex, createdAt: Date())).frame(height: 240)
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
                Text("Your first plant starts small. Over the next three days, Pot will learn your rhythm. Rest days are welcome.")
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
    @State private var confirmErase = false
    @State private var alias = ""
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
            if model.selected != nil {
                Section("This plant") {
                    TextField("Name", text: $alias).onSubmit { model.rename(alias) }
                    Button("Save name") { model.rename(alias) }
                }
            }
            Section("Garden") {
                Toggle("Pause the garden", isOn: $model.gardenPaused)
                Text("For holidays and breaks. Growth and wilting stop until you resume; statistics keep counting.")
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
            Section("About Pot") {
                Text("Pot 0.1.0 · A little plant on your Mac.")
                Text("Usage and plants stay on this Mac. Records may contain conversations; Pot keeps only usage metrics. Prices are bundled reference rates, not your bill. Unknown models remain unpriced.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Check for updates…") {
                    NSWorkspace.shared.open(URL(string: "https://github.com/ClementeBobillier07/pot/releases")!)
                }
                Text("Opens GitHub in your browser. Pot does not install updates automatically.").font(.caption).foregroundStyle(.secondary)
                Button("Export garden and daily totals…") { model.exportGarden() }.disabled(model.busy || model.snapshots.isEmpty)
                Text("Saves a JSON file you control: daily token totals, estimated values and plant state. No conversations, paths or account identifiers.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Delete local data and plants…", role: .destructive) { confirmErase = true }.disabled(model.busy)
                Button("Quit Pot") { NSApp.terminate(nil) }
            }
        }.formStyle(.grouped)
        .task(id: model.selected?.profile.id) { alias = model.selected?.profile.alias ?? "" }
        .confirmationDialog("Delete your local garden?", isPresented: $confirmErase, titleVisibility: .visible) {
            Button("Delete all Pot data", role: .destructive) { model.eraseData() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("This removes Pot’s usage history, plants and preferences. Agent logs are untouched. Reimporting logs starts a new garden; records already removed by your agents cannot be recovered.") }
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
                            PlantView(plant: snap.plant, active: model.mainVisible && recentlyActive(snap), idle: model.mainVisible)
                                .frame(width: 150, height: 176)
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
    private var accumulation = 0.0
    private var lastNavigation = Date.distantPast
    init(navigate: @escaping (Int) -> Void) {
        self.navigate = navigate; super.init(frame: .zero)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self, event.window === self.window,
                  abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) * 1.5,
                  Date().timeIntervalSince(self.lastNavigation) > 0.6 else { return event }
            self.accumulation += event.scrollingDeltaX
            if abs(self.accumulation) > 65 {
                self.navigate(self.accumulation > 0 ? -1 : 1)
                self.accumulation = 0; self.lastNavigation = Date()
            }
            return event
        }
    }
    required init?(coder: NSCoder) { nil }
    deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
#endif
