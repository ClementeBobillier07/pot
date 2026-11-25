#if os(macOS)
import AppKit
import SwiftUI
import Combine
import PotCore

extension Notification.Name { static let potResetPosition = Notification.Name("Pot.resetFloatingPosition") }

private final class PlantPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class FloatingInteraction: ObservableObject {
    @Published var hovered = false
}

@MainActor
final class FloatingPlantController {
    private let model: AppModel
    private let panel: PlantPanel
    private let interaction = FloatingInteraction()
    private var subscription: AnyCancellable?
    private var notifications: [NSObjectProtocol] = []
    private var pointerTimer: Timer?
    private var lastSize: CGFloat = 0
    private var visibilityGeneration = 0

    init(model: AppModel) {
        self.model = model
        panel = PlantPanel(contentRect: NSRect(x: 0, y: 0, width: 212, height: 261),
                           styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
        panel.level = .floating; panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isMovableByWindowBackground = false; panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: FloatingPlantView(model: model, interaction: interaction, moved: { [weak self] in self?.savePosition() }))
        subscription = model.objectWillChange.sink { [weak self] in
            DispatchQueue.main.async { self?.update() }
        }
        let center = NotificationCenter.default
        notifications.append(center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.clampToScreens() }
        })
        notifications.append(center.addObserver(forName: .potResetPosition, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.positionInitially() }
        })
        notifications.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.clampToScreens(); self?.model.scan() }
        })
        update()
        positionInitially()
    }
    private func update() {
        let width = CGFloat(model.plantSize)
        if lastSize != width {
            panel.setContentSize(NSSize(width: width + 32, height: width * 1.25 + 36))
            lastSize = width; clampToScreens()
        }
        let wantsVisible = model.floatingVisible
        if wantsVisible && !panel.isVisible {
            visibilityGeneration += 1
            panel.alphaValue = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 1 : 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in context.duration = 0.2; panel.animator().alphaValue = 1 }
            startPointerTracking()
        } else if !wantsVisible && panel.isVisible {
            visibilityGeneration += 1
            let generation = visibilityGeneration
            pointerTimer?.invalidate(); pointerTimer = nil; interaction.hovered = false
            if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                panel.orderOut(nil)
            } else {
                NSAnimationContext.runAnimationGroup({ context in context.duration = 0.18; panel.animator().alphaValue = 0 }) { [weak self] in
                    Task { @MainActor in
                        guard let self, self.visibilityGeneration == generation, !self.model.floatingVisible else { return }
                        self.panel.orderOut(nil)
                    }
                }
            }
        } else if wantsVisible && panel.alphaValue < 1 {
            // Cancel a stale hide completion if activity resumes during its fade.
            visibilityGeneration += 1
            panel.alphaValue = 1; startPointerTracking()
        }
        updateHitTesting()
    }
    private func positionInitially() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: "floatingX") != nil, defaults.object(forKey: "floatingY") != nil {
            panel.setFrameOrigin(NSPoint(x: defaults.double(forKey: "floatingX"), y: defaults.double(forKey: "floatingY")))
        } else if let screen = NSScreen.main {
            panel.setFrameOrigin(NSPoint(x: screen.visibleFrame.maxX - panel.frame.width - 20, y: screen.visibleFrame.minY + 20))
        }
        clampToScreens()
    }
    private func clampToScreens() {
        let frame = panel.frame
        let screen = NSScreen.screens.max { a, b in
            let ia = a.visibleFrame.intersection(frame), ib = b.visibleFrame.intersection(frame)
            return ia.width * ia.height < ib.width * ib.height
        } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        panel.setFrameOrigin(NSPoint(x: max(visible.minX, min(frame.minX, visible.maxX - frame.width)), y: max(visible.minY, min(frame.minY, visible.maxY - frame.height))))
    }
    private func savePosition() {
        clampToScreens()
        UserDefaults.standard.set(panel.frame.minX, forKey: "floatingX")
        UserDefaults.standard.set(panel.frame.minY, forKey: "floatingY")
    }
    private func startPointerTracking() {
        guard pointerTimer == nil else { return }
        // Only a visible plant checks the pointer; no render loop or global event tap is needed.
        pointerTimer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updateHitTesting() }
        }
    }
    private func updateHitTesting() {
        guard panel.isVisible, let plant = model.selected?.plant else { return }
        let point = panel.convertPoint(fromScreen: NSEvent.mouseLocation)
        let insideWindow = NSRect(origin: .zero, size: panel.frame.size).contains(point)
        let hit: Bool
        if interaction.hovered && insideWindow {
            hit = true // Keep the controls reachable between leaves and their buttons.
        } else {
            let w = CGFloat(model.plantSize), s = w / 320
            let normalized = CGPoint(x: (point.x - 16) / s, y: (panel.frame.height - point.y - 4) / s)
            hit = insideWindow && plantContains(normalized, plant: plant)
        }
        if interaction.hovered != hit { interaction.hovered = hit }
        panel.ignoresMouseEvents = !hit
    }
    /// Transparent blank space passes through until the pointer enters the plant silhouette.
    private func plantContains(_ point: CGPoint, plant: PlantState) -> Bool {
        if CGRect(x: 95, y: 308, width: 130, height: 85).contains(point) { return true }
        for organ in plant.organs {
            let start = CGPoint(x: organ.x * 320, y: organ.y * 400)
            if organ.kind == .stem || organ.kind == .branch {
                let end = CGPoint(x: organ.endpoint.x * 320, y: organ.endpoint.y * 400)
                let dx = end.x - start.x, dy = end.y - start.y
                let length = max(1, dx * dx + dy * dy)
                let t = max(0, min(1, ((point.x - start.x) * dx + (point.y - start.y) * dy) / length))
                if hypot(point.x - start.x - t * dx, point.y - start.y - t * dy) < 8 { return true }
            } else if organ.kind == .leaf {
                let dx = point.x - start.x, dy = point.y - start.y
                let cosA = cos(organ.orientation), sinA = sin(organ.orientation)
                let x = dx * cosA + dy * sinA, y = -dx * sinA + dy * cosA
                let length = 9 + organ.size * 5.5, width = length * (plant.provider == .codex ? 0.62 : 0.38)
                if pow(x / max(8, width), 2) + pow((y + length / 2) / (length / 2 + 4), 2) <= 1 { return true }
            } else if hypot(point.x - start.x, point.y - start.y) < 10 + organ.size * 2 { return true }
        }
        return false
    }
    deinit {
        pointerTimer?.invalidate()
        for token in notifications { NotificationCenter.default.removeObserver(token); NSWorkspace.shared.notificationCenter.removeObserver(token) }
    }
}

private struct FloatingPlantView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var interaction: FloatingInteraction
    let moved: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        ZStack(alignment: .topTrailing) {
            if let selected = model.selected {
                VStack(spacing: 0) {
                    PlantView(plant: selected.plant, active: model.floatingVisible && recentlyActive(selected))
                        .frame(width: model.plantSize, height: model.plantSize * 1.25)
                        .overlay(PlantDragSurface(clicked: { model.openMain?() }, moved: moved))
                        .accessibilityAction { model.openMain?() }
                    HStack(spacing: 34) {
                        if model.snapshots.count > 1 {
                            Button { model.navigate(-1) } label: { Image(systemName: "chevron.left") }.accessibilityLabel("Previous plant")
                            Button { model.navigate(1) } label: { Image(systemName: "chevron.right") }.accessibilityLabel("Next plant")
                        }
                    }.frame(height: 28).opacity(interaction.hovered ? 1 : 0).allowsHitTesting(interaction.hovered)
                }.padding(.horizontal, 16).padding(.top, 4)
                Button { model.hideFloating() } label: {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .semibold)).frame(width: 24, height: 24)
                }.padding(.trailing, 5).opacity(interaction.hovered ? 1 : 0).allowsHitTesting(interaction.hovered)
                    .accessibilityLabel("Hide floating plant")
            }
        }
        .frame(width: model.plantSize + 32, height: model.plantSize * 1.25 + 36)
        .buttonStyle(.plain)
        .foregroundStyle(model.appearance == "dark" ? Color.white.opacity(0.8) : Color.primary.opacity(0.65))
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: interaction.hovered)
        .preferredColorScheme(model.colorScheme)
        .background(Color.clear)
    }
    private func recentlyActive(_ selected: AccountSnapshot) -> Bool {
        selected.lastActivity.map { Date().timeIntervalSince($0) >= 0 && Date().timeIntervalSince($0) < 90 } ?? false
    }
}

private struct PlantDragSurface: NSViewRepresentable {
    let clicked: () -> Void
    let moved: () -> Void
    func makeNSView(context: Context) -> DragSurfaceView { DragSurfaceView(clicked: clicked, moved: moved) }
    func updateNSView(_ view: DragSurfaceView, context: Context) { view.clicked = clicked; view.moved = moved }
}
private final class DragSurfaceView: NSView {
    var clicked: () -> Void
    var moved: () -> Void
    private var startMouse = NSPoint.zero
    private var startOrigin = NSPoint.zero
    private var dragged = false
    init(clicked: @escaping () -> Void, moved: @escaping () -> Void) {
        self.clicked = clicked; self.moved = moved; super.init(frame: .zero)
        setAccessibilityElement(false)
    }
    required init?(coder: NSCoder) { nil }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { startMouse = NSEvent.mouseLocation; startOrigin = window?.frame.origin ?? .zero; dragged = false }
    override func mouseDragged(with event: NSEvent) {
        let point = NSEvent.mouseLocation
        let dx = point.x - startMouse.x, dy = point.y - startMouse.y
        if hypot(dx, dy) >= 4 { dragged = true }
        if dragged { window?.setFrameOrigin(NSPoint(x: startOrigin.x + dx, y: startOrigin.y + dy)) }
    }
    override func mouseUp(with event: NSEvent) { if dragged { moved() } else { clicked() } }
}
#endif
