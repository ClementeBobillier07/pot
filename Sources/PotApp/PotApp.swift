#if os(macOS)
import AppKit
import SwiftUI
import PotCore

/// Pure AppKit lifecycle. A SwiftUI `App` needs at least one scene, and its placeholder
/// `Settings { EmptyView() }` opened an empty "Pot Settings" window at launch on macOS.
/// Pot's windows (main window, floating plant, status item) are all owned by PotDelegate.
@main
enum PotApplication {
    @MainActor private static var delegate: PotDelegate?
    static func main() {
        MainActor.assumeIsolated {
            let app = NSApplication.shared
            let potDelegate = PotDelegate()
            delegate = potDelegate
            app.delegate = potDelegate
            app.run()
        }
    }
}

@MainActor
final class PotDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var statusItem: NSStatusItem!
    private var window: NSWindow!
    private var panel: FloatingPlantController!
    private var model: AppModel!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NSApp.mainMenu = Self.makeMainMenu()
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
        // Development/QA convenience: `swift run Pot --show-window` opens the garden directly.
        if CommandLine.arguments.contains("--show-window") { openMain() }
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
        let presentation = NSMenuItem(title: "Presentation", action: nil, keyEquivalent: "")
        let modes = NSMenu()
        for mode in DisplayMode.allCases {
            let item = NSMenuItem(title: mode.title, action: #selector(choosePresentation(_:)), keyEquivalent: "")
            item.representedObject = mode.rawValue
            item.state = model.mode == mode ? .on : .off
            item.target = self
            modes.addItem(item)
        }
        presentation.submenu = modes
        menu.addItem(presentation)
        menu.addItem(withTitle: model.gardenPaused ? "Resume garden" : "Pause garden", action: #selector(togglePause), keyEquivalent: "")
        menu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Pot", action: #selector(quitPot), keyEquivalent: "q")
        for item in menu.items where item.action != nil { item.target = self }
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }
    /// Invisible for an accessory app, but required for standard key equivalents
    /// (copy/paste in the alias field, ⌘W, ⌘Q) once there is no SwiftUI scene.
    private static func makeMainMenu() -> NSMenu {
        let main = NSMenu()
        let appItem = NSMenuItem(); let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Pot", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu; main.addItem(appItem)
        let editItem = NSMenuItem(); let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit; main.addItem(editItem)
        let windowItem = NSMenuItem(); let window = NSMenu(title: "Window")
        window.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowItem.submenu = window; main.addItem(windowItem)
        return main
    }
    @objc private func showMain() { openMain() }
    @objc private func showSettings() { model.showSettings = true; openMain() }
    @objc private func togglePlant() { model.toggleFloating() }
    @objc private func togglePause() { model.gardenPaused.toggle() }
    @objc private func choosePresentation(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let mode = DisplayMode(rawValue: raw) else { return }
        model.mode = mode
    }
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
