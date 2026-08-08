import Foundation
import XCTest

final class ShaderEdgeCoverageTests: XCTestCase {
    func testOuterMaskKeepsTheViewportBoundaryOpaque() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let rendererURL = repositoryRoot
            .appendingPathComponent("Sources")
            .appendingPathComponent("WindowCRTLensApp")
            .appendingPathComponent("CRTRenderer.swift")
        let rendererSource = try String(contentsOf: rendererURL, encoding: .utf8)

        XCTAssertTrue(
            rendererSource.contains(
                "float outerCoverage = 1.0 - smoothstep(0.0, outerAA, outerDistance);"
            ),
            "The outer mask must remain opaque at and inside its boundary, then antialias outward."
        )
        XCTAssertFalse(
            rendererSource.contains(
                "float outerCoverage = 1.0 - smoothstep(-outerAA, outerAA, outerDistance);"
            ),
            "Centered antialiasing makes the viewport's outermost pixel 50% transparent."
        )
    }

    func testRoundedCornersCompositeOverAnOpaqueCRTMatte() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let rendererURL = repositoryRoot
            .appendingPathComponent("Sources")
            .appendingPathComponent("WindowCRTLensApp")
            .appendingPathComponent("CRTRenderer.swift")
        let rendererSource = try String(contentsOf: rendererURL, encoding: .utf8)

        XCTAssertTrue(
            rendererSource.contains(
                "color = mix(float3(0.006, 0.007, 0.01), color, outerCoverage);"
            ),
            "Pixels outside the rounded shell must blend into the CRT matte, not the source window."
        )
        XCTAssertTrue(
            rendererSource.contains("return float4(color, 1.0);"),
            "The final overlay must stay opaque so the rectangular source cannot show through its corners."
        )
        XCTAssertFalse(
            rendererSource.contains("return float4(color, outerCoverage);"),
            "Using shell coverage as alpha exposes the real source window behind rounded corners."
        )
    }
}
