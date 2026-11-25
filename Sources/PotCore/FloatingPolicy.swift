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

/// Screen corner chosen during onboarding for the floating plant (master doc §3 step 4, §10).
public enum FloatingCorner: String, Codable, CaseIterable, Sendable {
    case bottomRight, bottomLeft, topRight, topLeft
    public var title: String {
        switch self {
        case .bottomRight: return "Bottom right"
        case .bottomLeft: return "Bottom left"
        case .topRight: return "Top right"
        case .topLeft: return "Top left"
        }
    }
    /// Origin of a window of `size` inside `visible` (AppKit coordinates, origin bottom-left).
    public func origin(windowWidth: Double, windowHeight: Double, visibleMinX: Double, visibleMinY: Double, visibleMaxX: Double, visibleMaxY: Double, margin: Double = 20) -> (x: Double, y: Double) {
        let left = visibleMinX + margin, right = visibleMaxX - windowWidth - margin
        let bottom = visibleMinY + margin, top = visibleMaxY - windowHeight - margin
        switch self {
        case .bottomRight: return (right, bottom)
        case .bottomLeft: return (left, bottom)
        case .topRight: return (right, top)
        case .topLeft: return (left, top)
        }
    }
}
