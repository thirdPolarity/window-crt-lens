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
        XCTAssertEqual(LensPreset.allCases.map(\.id), ["subtle", "glassy", "bulbous"])

        for preset in LensPreset.allCases {
            XCTAssertTrue((0...0.14).contains(preset.curvature))
            XCTAssertTrue((0...0.45).contains(preset.scanlineStrength))
            XCTAssertTrue((0...0.25).contains(preset.maskStrength))
            XCTAssertTrue((0...0.35).contains(preset.glowStrength))
            XCTAssertTrue((0...0.55).contains(preset.vignetteStrength))
        }
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
