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
        window.collectionBehavior = [
            .managed,
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .ignoresCycle,
        ]
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

public enum LensGeometryTransitionPolicy {
    public static func isReady(captureFrame: CGRect, targetFrame: CGRect) -> Bool {
        captureFrame == targetFrame
    }
}

public enum LensWarpStyle: Float, Sendable {
    case radial = 0
    case axisCubic = 1
}

public enum PhosphorMaskStyle: Float, Sendable {
    case legacyApertureGrille = -1
    case apertureGrille = 0
    case shadowMask = 1
    case slotMask = 2
    case monochrome = 3
}

public struct LensPresetProfile: Equatable, Sendable {
    public let curvature: SIMD2<Float>
    public let warpStyle: LensWarpStyle
    public let scanlineStrength: Float
    public let maskStrength: Float
    public let maskStyle: PhosphorMaskStyle
    public let maskPitch: Float
    public let glowStrength: Float
    public let halationStrength: Float
    public let halationRadius: Float
    public let vignetteStrength: Float
    public let glassStrength: Float
    public let brightness: Float
    public let phosphorTint: SIMD3<Float>
    public let monochromeMix: Float
}

public enum LensPreset: String, CaseIterable, Identifiable, Sendable {
    case subtle
    case glassy
    case bulbous
    case deepTube
    case rooftopArcade
    case apertureGrille
    case amberTerminal

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .subtle: "Subtle Terminal"
        case .glassy: "Glassy CRT"
        case .bulbous: "Bulbous Glass"
        case .deepTube: "Deep Consumer Tube"
        case .rooftopArcade: "Rooftop Arcade"
        case .apertureGrille: "PVM Aperture Grille"
        case .amberTerminal: "Amber Terminal"
        }
    }

    public var profile: LensPresetProfile {
        switch self {
        case .subtle:
            LensPresetProfile(
                curvature: SIMD2(repeating: 0.018),
                warpStyle: .radial,
                scanlineStrength: 0.16,
                maskStrength: 0.035,
                maskStyle: .legacyApertureGrille,
                maskPitch: 1,
                glowStrength: 0.06,
                halationStrength: 0,
                halationRadius: 1,
                vignetteStrength: 0.12,
                glassStrength: 1,
                brightness: 1,
                phosphorTint: SIMD3(repeating: 1),
                monochromeMix: 0
            )
        case .glassy:
            LensPresetProfile(
                curvature: SIMD2(repeating: 0.055),
                warpStyle: .radial,
                scanlineStrength: 0.24,
                maskStrength: 0.08,
                maskStyle: .legacyApertureGrille,
                maskPitch: 1,
                glowStrength: 0.12,
                halationStrength: 0,
                halationRadius: 1,
                vignetteStrength: 0.26,
                glassStrength: 1,
                brightness: 1,
                phosphorTint: SIMD3(repeating: 1),
                monochromeMix: 0
            )
        case .bulbous:
            LensPresetProfile(
                curvature: SIMD2(repeating: 0.11),
                warpStyle: .radial,
                scanlineStrength: 0.28,
                maskStrength: 0.10,
                maskStyle: .legacyApertureGrille,
                maskPitch: 1,
                glowStrength: 0.16,
                halationStrength: 0,
                halationRadius: 1,
                vignetteStrength: 0.42,
                glassStrength: 1,
                brightness: 1,
                phosphorTint: SIMD3(repeating: 1),
                monochromeMix: 0
            )
        case .deepTube:
            LensPresetProfile(
                curvature: SIMD2(0.15, 0.19),
                warpStyle: .axisCubic,
                scanlineStrength: 0.27,
                maskStrength: 0.20,
                maskStyle: .slotMask,
                maskPitch: 3,
                glowStrength: 0.15,
                halationStrength: 0.075,
                halationRadius: 2.2,
                vignetteStrength: 0.48,
                glassStrength: 0.92,
                brightness: 1.08,
                phosphorTint: SIMD3(1.03, 0.98, 0.92),
                monochromeMix: 0
            )
        case .rooftopArcade:
            LensPresetProfile(
                curvature: SIMD2(0.22, 0.18),
                warpStyle: .axisCubic,
                scanlineStrength: 0.34,
                maskStrength: 0.46,
                maskStyle: .shadowMask,
                maskPitch: 3.5,
                glowStrength: 0.09,
                halationStrength: 0.035,
                halationRadius: 1.5,
                vignetteStrength: 0.60,
                glassStrength: 0.62,
                brightness: 1.22,
                phosphorTint: SIMD3(1.04, 1, 0.96),
                monochromeMix: 0
            )
        case .apertureGrille:
            LensPresetProfile(
                curvature: SIMD2(repeating: 0.025),
                warpStyle: .radial,
                scanlineStrength: 0.20,
                maskStrength: 0.30,
                maskStyle: .apertureGrille,
                maskPitch: 2.5,
                glowStrength: 0.10,
                halationStrength: 0.04,
                halationRadius: 1.4,
                vignetteStrength: 0.16,
                glassStrength: 0.48,
                brightness: 1.10,
                phosphorTint: SIMD3(0.98, 1.02, 1.04),
                monochromeMix: 0
            )
        case .amberTerminal:
            LensPresetProfile(
                curvature: SIMD2(0.075, 0.10),
                warpStyle: .axisCubic,
                scanlineStrength: 0.22,
                maskStrength: 0.10,
                maskStyle: .monochrome,
                maskPitch: 2.8,
                glowStrength: 0.14,
                halationStrength: 0.10,
                halationRadius: 2.6,
                vignetteStrength: 0.30,
                glassStrength: 0.68,
                brightness: 1.08,
                phosphorTint: SIMD3(1, 0.56, 0.14),
                monochromeMix: 1
            )
        }
    }

    public var curvatureX: Float { profile.curvature.x }
    public var curvatureY: Float { profile.curvature.y }
    public var warpStyle: LensWarpStyle { profile.warpStyle }
    public var scanlineStrength: Float { profile.scanlineStrength }
    public var maskStrength: Float { profile.maskStrength }
    public var maskStyle: PhosphorMaskStyle { profile.maskStyle }
    public var maskPitch: Float { profile.maskPitch }
    public var glowStrength: Float { profile.glowStrength }
    public var halationStrength: Float { profile.halationStrength }
    public var halationRadius: Float { profile.halationRadius }
    public var vignetteStrength: Float { profile.vignetteStrength }
    public var glassStrength: Float { profile.glassStrength }
    public var brightness: Float { profile.brightness }
    public var phosphorTint: SIMD3<Float> { profile.phosphorTint }
    public var monochromeMix: Float { profile.monochromeMix }
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
        let hasStableTitle = !candidate.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return candidate.ownerPID != excludingPID
            && (candidate.isOnScreen || hasStableTitle)
            && candidate.frame.width >= 100
            && candidate.frame.height >= 100
            && !excludedBundleIdentifiers.contains(candidate.bundleIdentifier)
    }
}

public enum WindowSelectionReadiness {
    public static func isReady(
        isOnScreen: Bool,
        targetProcessID: pid_t,
        frontmostProcessID: pid_t?
    ) -> Bool {
        isOnScreen && frontmostProcessID == targetProcessID
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
