#if os(macOS)
import AppKit
import Sparkle

/// Signed updates through Sparkle (decision 31).
///
/// "Update automatically" on (the default): Sparkle checks the appcast once a day, downloads a new
/// version in the background, verifies its EdDSA signature and Developer ID, and Pot installs it and
/// relaunches as soon as its window is closed. Off: Pot never checks on its own; Settings shows
/// "Check for updates…". Requests carry only the app version; no usage, accounts or system profile.
@MainActor
final class UpdateController: NSObject, ObservableObject, SPUUpdaterDelegate {
    static let shared = UpdateController()
    /// Nil in development runs (`swift run Pot`), which have no bundle, feed or public key.
    private var controller: SPUStandardUpdaterController?
    private var pendingInstall: (() -> Void)?
    private var windowObserver: NSObjectProtocol?
    /// True while the person has Pot's window open; installation waits so Pot never relaunches under them.
    var isInUse: () -> Bool = { false }

    @Published private(set) var automatic = true
    @Published private(set) var canCheck = false
    var available: Bool { controller != nil }

    private override init() {
        super.init()
        let info = Bundle.main.infoDictionary ?? [:]
        guard Bundle.main.bundleURL.pathExtension == "app",
              info["SUFeedURL"] as? String != nil, info["SUPublicEDKey"] as? String != nil else { return }
        let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)
        self.controller = controller
        controller.updater.publisher(for: \.canCheckForUpdates).receive(on: RunLoop.main).assign(to: &$canCheck)
        controller.startUpdater()
        automatic = controller.updater.automaticallyChecksForUpdates && controller.updater.automaticallyDownloadsUpdates
        windowObserver = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { [weak self] _ in
            // Let the window finish closing before deciding.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { MainActor.assumeIsolated { self?.installIfIdle() } }
        }
    }

    func setAutomatic(_ on: Bool) {
        guard let updater = controller?.updater else { return }
        updater.automaticallyChecksForUpdates = on
        updater.automaticallyDownloadsUpdates = on
        automatic = on
        if on { updater.checkForUpdatesInBackground() }
    }

    /// Shows Sparkle's standard window: "You're up to date" or the new version with Install.
    func checkNow() {
        NSApp.activate()
        controller?.checkForUpdates(nil)
    }

    // MARK: SPUUpdaterDelegate

    /// A downloaded update is ready. Taking over means Sparkle shows no prompt; Pot installs it
    /// itself once nobody is looking at its window (the floating plant just blinks back).
    nonisolated func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem, immediateInstallationBlock: @escaping () -> Void) -> Bool {
        MainActor.assumeIsolated {
            guard automatic else { return false }
            pendingInstall = immediateInstallationBlock
            installIfIdle()
            return true
        }
    }

    private func installIfIdle() {
        guard let install = pendingInstall, !isInUse() else { return }
        pendingInstall = nil
        install()
    }
}
#endif
