import AppKit

public struct LensAppearance: Equatable, Sendable {
    public static let screenCornerRange = 0.0...80.0
    public static let shellCornerRange = 0.0...96.0
    public static let edgeSoftnessRange = 0.5...4.0
    public static let zoomRange = 0.85...1.50
    public static let defaultCornerGap = 1.0
    public static let `default` = LensAppearance(
        screenCornerRadius: 12,
        shellCornerRadius: 13,
        edgeSoftness: 1.25,
        zoom: 1
    )

    public let screenCornerRadius: Double
    public let shellCornerRadius: Double
    public let edgeSoftness: Double
    public let zoom: Double

    public init(
        screenCornerRadius: Double,
        shellCornerRadius: Double,
        edgeSoftness: Double,
        zoom: Double
    ) {
        self.screenCornerRadius = screenCornerRadius.clamped(to: Self.screenCornerRange)
        self.shellCornerRadius = shellCornerRadius.clamped(to: Self.shellCornerRange)
        self.edgeSoftness = edgeSoftness.clamped(to: Self.edgeSoftnessRange)
        self.zoom = zoom.clamped(to: Self.zoomRange)
    }

    public func renderMetrics(drawableSize: CGSize, viewSize: CGSize) -> LensAppearanceRenderMetrics {
        let xScale = viewSize.width > 0 ? drawableSize.width / viewSize.width : 1
        let yScale = viewSize.height > 0 ? drawableSize.height / viewSize.height : 1
        let scale = max(min(xScale, yScale), 0.1)
        return LensAppearanceRenderMetrics(
            screenCornerRadiusPixels: Float(screenCornerRadius * scale),
            shellCornerRadiusPixels: Float(shellCornerRadius * scale),
            edgeSoftnessPixels: Float(edgeSoftness * scale),
            zoomScale: Float(zoom)
        )
    }
}

public struct LensAppearanceRenderMetrics: Equatable, Sendable {
    public let screenCornerRadiusPixels: Float
    public let shellCornerRadiusPixels: Float
    public let edgeSoftnessPixels: Float
    public let zoomScale: Float
}

public final class LensAppearanceStore {
    private enum Key {
        static let screenCornerRadius = "appearance.screenCornerRadius"
        static let shellCornerRadius = "appearance.shellCornerRadius"
        static let edgeSoftness = "appearance.edgeSoftness"
        static let zoom = "appearance.zoom"
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> LensAppearance {
        guard defaults.object(forKey: Key.screenCornerRadius) != nil,
              defaults.object(forKey: Key.shellCornerRadius) != nil,
              defaults.object(forKey: Key.edgeSoftness) != nil,
              defaults.object(forKey: Key.zoom) != nil else {
            return .default
        }
        return LensAppearance(
            screenCornerRadius: defaults.double(forKey: Key.screenCornerRadius),
            shellCornerRadius: defaults.double(forKey: Key.shellCornerRadius),
            edgeSoftness: defaults.double(forKey: Key.edgeSoftness),
            zoom: defaults.double(forKey: Key.zoom)
        )
    }

    public func save(_ appearance: LensAppearance) {
        defaults.set(appearance.screenCornerRadius, forKey: Key.screenCornerRadius)
        defaults.set(appearance.shellCornerRadius, forKey: Key.shellCornerRadius)
        defaults.set(appearance.edgeSoftness, forKey: Key.edgeSoftness)
        defaults.set(appearance.zoom, forKey: Key.zoom)
    }
}

public final class PassiveOverlayWindow: NSWindow {
    public override var canBecomeKey: Bool { false }
    public override var canBecomeMain: Bool { false }
}

public enum OverlayContract {
    public static let overlayLevel = NSWindow.Level.floating
    public static let settingsPanelLevel = NSWindow.Level.modalPanel

    @MainActor
    public static func configure(_ window: NSWindow) {
        window.ignoresMouseEvents = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = overlayLevel
        window.collectionBehavior = [.managed, .fullScreenAuxiliary, .ignoresCycle]
    }
}

public enum WindowCoordinateMapper {
    public static func appKitFrame(
        for quartzFrame: CGRect,
        primaryDisplayHeight: CGFloat
    ) -> NSRect {
        NSRect(
            x: quartzFrame.origin.x,
            y: primaryDisplayHeight - quartzFrame.origin.y - quartzFrame.height,
            width: max(quartzFrame.width, 1),
            height: quartzFrame.height
        )
    }
}

public enum LensVisibilityPolicy {
    public static func shouldShow(
        targetProcessID: pid_t,
        ownProcessID: pid_t,
        frontmostProcessID: pid_t?
    ) -> Bool {
        frontmostProcessID == targetProcessID || frontmostProcessID == ownProcessID
    }
}

public enum LensPreset: String, CaseIterable, Identifiable, Sendable {
    case subtle
    case glassy
    case bulbous

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .subtle: "Subtle Terminal"
        case .glassy: "Glassy CRT"
        case .bulbous: "Bulbous Glass"
        }
    }

    public var curvature: Float {
        switch self {
        case .subtle: 0.018
        case .glassy: 0.055
        case .bulbous: 0.11
        }
    }

    public var scanlineStrength: Float {
        switch self {
        case .subtle: 0.16
        case .glassy: 0.24
        case .bulbous: 0.28
        }
    }

    public var maskStrength: Float {
        switch self {
        case .subtle: 0.035
        case .glassy: 0.08
        case .bulbous: 0.10
        }
    }

    public var glowStrength: Float {
        switch self {
        case .subtle: 0.06
        case .glassy: 0.12
        case .bulbous: 0.16
        }
    }

    public var vignetteStrength: Float {
        switch self {
        case .subtle: 0.12
        case .glassy: 0.26
        case .bulbous: 0.42
        }
    }
}

public struct WindowCandidate: Equatable, Sendable {
    public let windowID: CGWindowID
    public let ownerPID: pid_t
    public let appName: String
    public let bundleIdentifier: String
    public let title: String
    public let frame: CGRect
    public let isOnScreen: Bool

    public init(
        windowID: CGWindowID,
        ownerPID: pid_t,
        appName: String,
        bundleIdentifier: String,
        title: String,
        frame: CGRect,
        isOnScreen: Bool
    ) {
        self.windowID = windowID
        self.ownerPID = ownerPID
        self.appName = appName
        self.bundleIdentifier = bundleIdentifier
        self.title = title
        self.frame = frame
        self.isOnScreen = isOnScreen
    }
}

public enum WindowCandidatePolicy {
    private static let excludedBundleIdentifiers: Set<String> = [
        "com.apple.controlcenter",
        "com.apple.dock",
        "com.apple.notificationcenterui",
        "com.apple.WindowManager",
    ]

    public static func isEligible(_ candidate: WindowCandidate, excludingPID: pid_t) -> Bool {
        candidate.ownerPID != excludingPID
            && candidate.isOnScreen
            && candidate.frame.width >= 100
            && candidate.frame.height >= 100
            && !excludedBundleIdentifiers.contains(candidate.bundleIdentifier)
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
