import AppKit
import XCTest
@testable import WindowCRTLensCore

@MainActor
final class OverlayContractTests: XCTestCase {
    func testOverlayCannotTakeFocusOrInterceptMouseInput() {
        let window = PassiveOverlayWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )

        OverlayContract.configure(window)

        XCTAssertTrue(window.ignoresMouseEvents)
        XCTAssertFalse(window.canBecomeKey)
        XCTAssertFalse(window.canBecomeMain)
        XCTAssertFalse(window.isOpaque)
        XCTAssertEqual(window.backgroundColor, .clear)
        XCTAssertFalse(window.hasShadow)
        XCTAssertEqual(window.level, .floating)
        XCTAssertTrue(window.collectionBehavior.contains(.managed))
        XCTAssertTrue(window.collectionBehavior.contains(.fullScreenAuxiliary))
        XCTAssertTrue(window.collectionBehavior.contains(.ignoresCycle))
        XCTAssertFalse(window.collectionBehavior.contains(.canJoinAllSpaces))
        XCTAssertFalse(window.collectionBehavior.contains(.stationary))
    }

    func testOverlayMatchesTheEntireSourceWindow() {
        let quartzFrame = CGRect(x: 120, y: 80, width: 800, height: 600)

        let appKitFrame = WindowCoordinateMapper.appKitFrame(
            for: quartzFrame,
            primaryDisplayHeight: 1_800
        )

        XCTAssertEqual(appKitFrame, NSRect(x: 120, y: 1_120, width: 800, height: 600))
    }

    func testLensPresetsStayWithinSafeRealtimeRanges() {
        XCTAssertEqual(
            LensPreset.allCases.map(\.id),
            [
                "subtle",
                "glassy",
                "bulbous",
                "deepTube",
                "rooftopArcade",
                "apertureGrille",
                "amberTerminal",
            ]
        )

        for preset in LensPreset.allCases {
            XCTAssertTrue((0...0.24).contains(preset.curvatureX))
            XCTAssertTrue((0...0.24).contains(preset.curvatureY))
            XCTAssertTrue((0...0.45).contains(preset.scanlineStrength))
            XCTAssertTrue((0...0.55).contains(preset.maskStrength))
            XCTAssertTrue((1...8).contains(preset.maskPitch))
            XCTAssertTrue((0...0.35).contains(preset.glowStrength))
            XCTAssertTrue((0...0.18).contains(preset.halationStrength))
            XCTAssertTrue((0...4).contains(preset.halationRadius))
            XCTAssertTrue((0...0.65).contains(preset.vignetteStrength))
            XCTAssertTrue((0...1).contains(preset.glassStrength))
            XCTAssertTrue((0.85...1.35).contains(preset.brightness))
            XCTAssertTrue((0...1).contains(preset.monochromeMix))
            XCTAssertTrue(preset.phosphorTint.x > 0)
            XCTAssertTrue(preset.phosphorTint.y > 0)
            XCTAssertTrue(preset.phosphorTint.z > 0)
        }
    }

    func testNewProfilesRepresentDistinctTubeTechnologies() {
        XCTAssertEqual(LensPreset.deepTube.warpStyle, .axisCubic)
        XCTAssertEqual(LensPreset.deepTube.maskStyle, .slotMask)

        XCTAssertEqual(LensPreset.rooftopArcade.warpStyle, .axisCubic)
        XCTAssertEqual(LensPreset.rooftopArcade.maskStyle, .shadowMask)

        XCTAssertEqual(LensPreset.apertureGrille.warpStyle, .radial)
        XCTAssertEqual(LensPreset.apertureGrille.maskStyle, .apertureGrille)

        XCTAssertEqual(LensPreset.amberTerminal.maskStyle, .monochrome)
        XCTAssertEqual(LensPreset.amberTerminal.monochromeMix, 1)
    }

    func testOriginalProfilesKeepTheirEstablishedGeometryAndStrengths() {
        XCTAssertEqual(LensPreset.subtle.curvatureX, 0.018)
        XCTAssertEqual(LensPreset.glassy.curvatureX, 0.055)
        XCTAssertEqual(LensPreset.bulbous.curvatureX, 0.11)
        XCTAssertEqual(LensPreset.subtle.maskStyle, .legacyApertureGrille)
        XCTAssertEqual(LensPreset.glassy.maskStyle, .legacyApertureGrille)
        XCTAssertEqual(LensPreset.bulbous.maskStyle, .legacyApertureGrille)
        XCTAssertEqual(LensPreset.subtle.scanlineStrength, 0.16)
        XCTAssertEqual(LensPreset.glassy.maskStrength, 0.08)
        XCTAssertEqual(LensPreset.bulbous.glowStrength, 0.16)
    }

    func testLensStaysVisibleForItsTargetOrItsOwnAppearancePanel() {
        XCTAssertTrue(
            LensVisibilityPolicy.shouldShow(
                targetProcessID: 200,
                ownProcessID: 100,
                frontmostProcessID: 200
            )
        )
        XCTAssertTrue(
            LensVisibilityPolicy.shouldShow(
                targetProcessID: 200,
                ownProcessID: 100,
                frontmostProcessID: 100
            )
        )
        XCTAssertFalse(
            LensVisibilityPolicy.shouldShow(
                targetProcessID: 200,
                ownProcessID: 100,
                frontmostProcessID: 300
            )
        )
    }

    func testAppearancePanelAlwaysSitsAboveTheLens() {
        XCTAssertGreaterThan(
            OverlayContract.settingsPanelLevel.rawValue,
            OverlayContract.overlayLevel.rawValue
        )
    }
}
