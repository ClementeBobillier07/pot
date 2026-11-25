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
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("pot").font(.system(size: 23, weight: .semibold, design: .serif))
                Spacer()
                if model.busy { ProgressView().controlSize(.small).accessibilityLabel("Refreshing local garden") }
                Button { model.showSettings.toggle() } label: { Image(systemName: model.showSettings ? "xmark" : "slider.horizontal.3") }
                    .buttonStyle(.plain).accessibilityLabel(model.showSettings ? "Close settings" : "Settings")
            }.padding(.horizontal, 26).padding(.vertical, 18)
            if model.showSettings {
                SettingsView(model: model)
            } else if !model.onboarded {
                OnboardingView(model: model)
            } else if let account = model.selected {
                accountView(account)
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
            if model.onboarded && !model.showSettings { model.navigate($0); selectedDate = nil }
        })
        .onChange(of: model.selectedID) { _, _ in selectedDate = nil }
        .onMoveCommand { direction in
            guard model.onboarded, !model.showSettings else { return }
            if direction == .left { model.navigate(-1) }
            if direction == .right { model.navigate(1) }
        }
    }

    private func accountView(_ account: AccountSnapshot) -> some View {
        let today = account.days.last
        let selected = selectedDate.flatMap { date in account.days.first { Calendar.current.isDate($0.date, inSameDayAs: date) } }
        let point = selected ?? today
        return ScrollView {
            VStack(spacing: 5) {
                Text(account.profile.provider.displayName).font(.system(size: 24, weight: .medium, design: .serif))
                Text(account.profile.email ?? account.profile.alias).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                PlantView(plant: account.plant, active: model.mainVisible && isActive(account)).frame(width: 290, height: 300)
                    .padding(.top, -6).padding(.bottom, 4)
                Text(point.map { $0.tokens.formatted() } ?? "0")
                    .font(.system(size: 32, weight: .light, design: .rounded)).monospacedDigit()
                Text(selected.map { "tokens · " + $0.date.formatted(.dateTime.month(.abbreviated).day()) } ?? "tokens today")
                    .font(.callout).foregroundStyle(.secondary)
                HStack(spacing: 5) {
                    Text(money(point?.estimatedUSD))
                    Text("Estimated API value\(point?.partial == true ? " · partial" : "")")
                }.font(.caption).foregroundStyle(.secondary).padding(.top, 3)
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
                HStack(spacing: 16) {
                    if model.snapshots.count > 1 {
                        Button { model.navigate(-1) } label: { Image(systemName: "chevron.left") }.accessibilityLabel("Previous plant")
                    }
                    Text("\((model.snapshots.firstIndex { $0.profile.id == account.profile.id } ?? 0) + 1) / \(model.snapshots.count)")
                        .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                    if model.snapshots.count > 1 {
                        Button { model.navigate(1) } label: { Image(systemName: "chevron.right") }.accessibilityLabel("Next plant")
                    }
                }.buttonStyle(.plain).padding(.top, 25).padding(.bottom, 12)
                if Date().timeIntervalSince(account.plant.createdAt) < 3 * 86400 {
                    Text("Getting to know your rhythm · day \(min(3, max(1, Int(Date().timeIntervalSince(account.plant.createdAt) / 86400) + 1))) of 3")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text(account.coverage).font(.caption).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).padding(.horizontal, 30)
                Text("Reference API rates · \(account.priceReference)")
                    .font(.caption).foregroundStyle(.secondary).padding(.bottom, 20)
            }
        }
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
                    VStack(alignment: .leading, spacing: 5) {
                        Toggle(provider.displayName, isOn: Binding(get: { model.enabledProviders.contains(provider) }, set: { model.setEnabled(provider, enabled: $0) }))
                        Text(model.detections.first { $0.provider == provider }?.status ?? "Refresh to find local sources").font(.caption).foregroundStyle(.secondary)
                        if let version = model.detections.first(where: { $0.provider == provider })?.version { Text(version).font(.caption).foregroundStyle(.secondary) }
                        Button("Choose log folder…") { model.chooseFolder(for: provider) }
                    }.padding(.vertical, 4)
                }
                Button("Refresh detection") { model.refreshDetection() }.disabled(model.busy)
                Button("Read public account details…") { model.refreshDetection(includeAccountDetails: true) }.disabled(model.busy)
                Text("Uses the agents’ own status commands. Optional Codex account lookup never requests login or token refresh; the installed client may contact its provider. Historical records stay unattributed unless they identify an account.")
                    .font(.caption).foregroundStyle(.secondary)
                if model.selected != nil {
                    TextField("Plant alias", text: $alias).onSubmit { model.rename(alias) }
                    Button("Save alias") { model.rename(alias) }
                }
            }
            Section("At home on your Mac") {
                Picker("Display mode", selection: $model.mode) { ForEach(DisplayMode.allCases, id: \.rawValue) { Text($0.title).tag($0) } }
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
                Button("Delete local data and plants…", role: .destructive) { confirmErase = true }.disabled(model.busy)
                Button("Quit Pot") { NSApp.terminate(nil) }
            }
        }.formStyle(.grouped)
        .onAppear { alias = model.selected?.profile.alias ?? "" }
        .confirmationDialog("Delete your local garden?", isPresented: $confirmErase, titleVisibility: .visible) {
            Button("Delete all Pot data", role: .destructive) { model.eraseData() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("This removes Pot’s usage history, plants and preferences. Agent logs are untouched. Reimporting logs starts a new garden; records already removed by your agents cannot be recovered.") }
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
