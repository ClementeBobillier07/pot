#if os(macOS)
import AppKit
import SwiftUI
import PotCore

@main
struct PotApplication: App {
    @NSApplicationDelegateAdaptor(PotDelegate.self) private var delegate
    var body: some Scene { Settings { EmptyView() } }
}

@MainActor
final class PotDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var statusItem: NSStatusItem!
    private var window: NSWindow!
    private var panel: FloatingPlantController!
    private var model: AppModel!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        model = AppModel()
        model.openMain = { [weak self] in self?.openMain() }
        panel = FloatingPlantController(model: model)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "leaf.fill", accessibilityDescription: "Pot")
            button.target = self
            button.action = #selector(statusClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 430, height: 720),
                          styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Pot"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.titlebarAppearsTransparent = true
        window.contentView = NSHostingView(rootView: MainView(model: model))
        window.center()
        if !model.onboarded { openMain() } else { model.refreshDetection() }
    }

    func openMain() {
        model.mainVisible = true
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func statusClicked(_ sender: Any?) {
        guard NSApp.currentEvent?.type == .rightMouseUp else { openMain(); return }
        let menu = NSMenu()
        menu.addItem(withTitle: "Open Pot", action: #selector(showMain), keyEquivalent: "")
        menu.addItem(withTitle: model.floatingManuallyHidden ? "Show floating plant" : "Hide floating plant", action: #selector(togglePlant), keyEquivalent: "")
        menu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Pot", action: #selector(quitPot), keyEquivalent: "q")
        for item in menu.items { item.target = self }
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }
    @objc private func showMain() { openMain() }
    @objc private func showSettings() { model.showSettings = true; openMain() }
    @objc private func togglePlant() { model.toggleFloating() }
    @objc private func quitPot() { NSApp.terminate(nil) }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func windowWillClose(_ notification: Notification) { model.mainVisible = false }
    func windowDidMiniaturize(_ notification: Notification) { model.mainVisible = false }
    func windowDidDeminiaturize(_ notification: Notification) { model.mainVisible = true }
    func applicationWillTerminate(_ notification: Notification) { model.shutdown() }
}
#else
import Foundation
@main
struct UnsupportedPlatform {
    static func main() {
        fputs("Pot requires macOS 14 or later. This Linux executable is only a platform guard, not the macOS application.\n", stderr)
    }
}
#endif
