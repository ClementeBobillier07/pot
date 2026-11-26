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
            panel.setContentSize(NSSize(width: width + 32, height: width * 1.25 + 8))
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
            // Corner chosen in onboarding/settings; visibleFrame already excludes Dock and menu bar.
            let v = screen.visibleFrame
            let o = model.corner.origin(windowWidth: panel.frame.width, windowHeight: panel.frame.height, visibleMinX: v.minX, visibleMinY: v.minY, visibleMaxX: v.maxX, visibleMaxY: v.maxY)
            panel.setFrameOrigin(NSPoint(x: o.x, y: o.y))
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
        let w = CGFloat(model.plantSize), s = w / 320
        let normalized = CGPoint(x: (point.x - 16) / s, y: (panel.frame.height - point.y - 4) / s)
        let hit: Bool
        if interaction.hovered && insideWindow {
            // Keep the close button reachable: stay hovered inside the plant's bounds plus the
            // button and a small margin, so empty transparent space elsewhere still passes clicks through.
            let zone = PlantLayout.visibleBounds(plant).insetBy(dx: -22 / s, dy: -26 / s)
            hit = zone.contains(normalized)
        } else {
            hit = insideWindow && plantContains(normalized, plant: plant)
        }
        if interaction.hovered != hit { interaction.hovered = hit }
        panel.ignoresMouseEvents = !hit
    }
    /// Transparent blank space passes through until the pointer enters the plant silhouette.
    private func plantContains(_ point: CGPoint, plant: PlantState) -> Bool {
        PlantLayout.contains(point, plant: plant)
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
                PlantView(plant: selected.plant, active: model.floatingVisible && recentlyActive(selected))
                    .frame(width: model.plantSize, height: model.plantSize * 1.25)
                    .id(selected.profile.id)
                    .transition(reduceMotion ? .opacity : PlantSwitch.transition(direction: model.navigationDirection))
                    .overlay(PlantDragSurface(clicked: { model.showGrid = false; model.showSettings = false; model.openMain?() }, moved: moved,
                                              navigate: { model.navigate($0) }))
                    .accessibilityAction { model.openMain?() }
                    .padding(.horizontal, 16).padding(.top, 4)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                // Only control on the desktop: a close button just above the plant's top-right edge.
                // Plants are switched inside Pot, not from the floating plant.
                CloseBadge { model.hideFloating() }
                    .position(closeCenter(selected.plant))
                    .opacity(interaction.hovered ? 1 : 0).allowsHitTesting(interaction.hovered)
            }
        }
        .frame(width: model.plantSize + 32, height: model.plantSize * 1.25 + 8)
        .buttonStyle(.plain)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: interaction.hovered)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.28), value: model.selectedID)
        .preferredColorScheme(model.colorScheme)
        .background(Color.clear)
    }
    private func closeCenter(_ plant: PlantState) -> CGPoint {
        let s = model.plantSize / 320
        let bounds = PlantLayout.visibleBounds(plant)
        let x = 16 + min(320, bounds.maxX) * s + 6
        let y = 4 + bounds.minY * s - 6
        return CGPoint(x: min(model.plantSize + 32 - 13, max(13, x)), y: max(13, y))
    }
    private func recentlyActive(_ selected: AccountSnapshot) -> Bool {
        selected.lastActivity.map { Date().timeIntervalSince($0) >= 0 && Date().timeIntervalSince($0) < 90 } ?? false
    }
}

/// Black ✕ in a white circle with a black outline: readable over light and dark desktops.
private struct CloseBadge: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(Color.white)
                Circle().strokeBorder(Color.black, lineWidth: 1.5)
                Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).foregroundStyle(Color.black)
            }
            .frame(width: 22, height: 22)
            .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help("Hide floating plant")
        .accessibilityLabel("Hide floating plant")
    }
}

private struct PlantDragSurface: NSViewRepresentable {
    let clicked: () -> Void
    let moved: () -> Void
    let navigate: (Int) -> Void
    func makeNSView(context: Context) -> DragSurfaceView { DragSurfaceView(clicked: clicked, moved: moved, navigate: navigate) }
    func updateNSView(_ view: DragSurfaceView, context: Context) { view.clicked = clicked; view.moved = moved; view.navigate = navigate }
}
private final class DragSurfaceView: NSView {
    var clicked: () -> Void
    var moved: () -> Void
    var navigate: (Int) -> Void
    private var startMouse = NSPoint.zero
    private var startOrigin = NSPoint.zero
    private var dragged = false
    init(clicked: @escaping () -> Void, moved: @escaping () -> Void, navigate: @escaping (Int) -> Void) {
        self.clicked = clicked; self.moved = moved; self.navigate = navigate; super.init(frame: .zero)
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
    /// Two-finger horizontal swipe over the plant switches plants, like in the Pot window.
    /// One switch per gesture: momentum is ignored and a short cooldown prevents skipping plants.
    override func scrollWheel(with event: NSEvent) {
        if let direction = MainActor.assumeIsolated({ SwipeGate.floating.direction(for: event) }) { navigate(direction) }
    }
}
#endif
