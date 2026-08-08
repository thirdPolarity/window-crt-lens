import CoreGraphics
import Foundation
import XCTest
@testable import WindowCRTLensCore

final class LensAppearanceTests: XCTestCase {
    func testAppearanceClampsValuesToSafeRealtimeRanges() {
        let appearance = LensAppearance(
            screenCornerRadius: 500,
            shellCornerRadius: -20,
            edgeSoftness: 20,
            zoom: 20
        )

        XCTAssertEqual(appearance.screenCornerRadius, LensAppearance.screenCornerRange.upperBound)
        XCTAssertEqual(appearance.shellCornerRadius, LensAppearance.shellCornerRange.lowerBound)
        XCTAssertEqual(appearance.edgeSoftness, LensAppearance.edgeSoftnessRange.upperBound)
        XCTAssertEqual(appearance.zoom, LensAppearance.zoomRange.upperBound)
    }

    func testDefaultCornersCreateAConcentricShell() {
        let appearance = LensAppearance.default

        XCTAssertEqual(appearance.screenCornerRadius, 12)
        XCTAssertEqual(appearance.shellCornerRadius, 13)
        XCTAssertEqual(appearance.edgeSoftness, 1.25)
        XCTAssertEqual(appearance.zoom, 1)
        XCTAssertGreaterThan(appearance.shellCornerRadius, appearance.screenCornerRadius)
        XCTAssertEqual(
            appearance.shellCornerRadius - appearance.screenCornerRadius,
            LensAppearance.defaultCornerGap,
            accuracy: 0.001
        )
    }

    func testRenderMetricsScalePointValuesForRetinaDrawables() {
        let appearance = LensAppearance(
            screenCornerRadius: 18,
            shellCornerRadius: 26,
            edgeSoftness: 1.25,
            zoom: 1.2
        )

        let metrics = appearance.renderMetrics(
            drawableSize: CGSize(width: 2_000, height: 1_200),
            viewSize: CGSize(width: 1_000, height: 600)
        )

        XCTAssertEqual(metrics.screenCornerRadiusPixels, 36, accuracy: 0.001)
        XCTAssertEqual(metrics.shellCornerRadiusPixels, 52, accuracy: 0.001)
        XCTAssertEqual(metrics.edgeSoftnessPixels, 2.5, accuracy: 0.001)
        XCTAssertEqual(metrics.zoomScale, 1.2, accuracy: 0.001)
    }

    func testAppearanceRoundTripsThroughItsStore() {
        let suiteName = "LensAppearanceTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Could not create isolated defaults")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = LensAppearanceStore(defaults: defaults)
        let expected = LensAppearance(
            screenCornerRadius: 31,
            shellCornerRadius: 44,
            edgeSoftness: 2.25,
            zoom: 1.18
        )

        store.save(expected)

        XCTAssertEqual(store.load(), expected)
    }

    func testOlderStoredAppearanceWithoutZoomMigratesToNewDefaults() {
        let suiteName = "LensAppearanceTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Could not create isolated defaults")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(18, forKey: "appearance.screenCornerRadius")
        defaults.set(28, forKey: "appearance.shellCornerRadius")
        defaults.set(1.25, forKey: "appearance.edgeSoftness")

        XCTAssertEqual(LensAppearanceStore(defaults: defaults).load(), .default)
    }
}
