import Foundation

public enum DisplayMode: String, Codable, CaseIterable, Sendable {
    case menuBarOnly, whileIWork, alwaysWithMe
    public var title: String {
        switch self {
        case .menuBarOnly: return "Menu bar only"
        case .whileIWork: return "While I work"
        case .alwaysWithMe: return "Always with me"
        }
    }
}

/// Presentation state only: visibility never changes selection, tokens or biology.
public struct FloatingPolicy: Sendable {
    public var mode: DisplayMode
    public var inactivityDelay: TimeInterval
    public private(set) var manuallyHidden = false
    private var activityWasRecent = false
    public init(mode: DisplayMode, inactivityDelay: TimeInterval = 180) {
        self.mode = mode
        self.inactivityDelay = inactivityDelay
    }
    public mutating func hide() { manuallyHidden = true }
    public mutating func show() { manuallyHidden = false }
    public mutating func visible(lastActivity: Date?, now: Date, hasPlant: Bool) -> Bool {
        let recent = lastActivity.map { now.timeIntervalSince($0) >= 0 && now.timeIntervalSince($0) < max(30, inactivityDelay) } ?? false
        // Manual dismissal lasts through the current work session, including repeated log pulses.
        if mode == .whileIWork && activityWasRecent && !recent { manuallyHidden = false }
        activityWasRecent = recent
        guard hasPlant, !manuallyHidden else { return false }
        switch mode {
        case .menuBarOnly: return false
        case .whileIWork: return recent
        case .alwaysWithMe: return true
        }
    }
}
