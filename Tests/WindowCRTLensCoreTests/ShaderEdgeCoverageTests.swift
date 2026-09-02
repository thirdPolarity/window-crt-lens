import Foundation
import XCTest

final class ShaderEdgeCoverageTests: XCTestCase {
    private func rendererSource() throws -> String {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let rendererURL = repositoryRoot
            .appendingPathComponent("Sources")
            .appendingPathComponent("WindowCRTLensApp")
            .appendingPathComponent("CRTRenderer.swift")
        return try String(contentsOf: rendererURL, encoding: .utf8)
    }

    func testShaderSupportsAxisCubicGlassAndMultiplePhosphorMasks() throws {
        let rendererSource = try rendererSource()

        XCTAssertTrue(
            rendererSource.contains(
                "float2 axisCurve = lensPosition * (1.0 + u.curvature * lensPosition.yx * lensPosition.yx);"
            )
        )
        XCTAssertTrue(rendererSource.contains("float3 phosphor_mask("))
        XCTAssertTrue(rendererSource.contains("u.maskStyle"))
    }

    func testDisplayGridStaysFixedWhileTheSourceImageWarpsAndZooms() throws {
        let rendererSource = try rendererSource()

        XCTAssertTrue(rendererSource.contains("float2 displayPixel = in.uv * u.outputSize;"))
        XCTAssertTrue(rendererSource.contains("sin(displayPixel.y * 3.14159265)"))
        XCTAssertTrue(rendererSource.contains("phosphor_mask(displayPixel, u.maskPitch, u.maskStyle)"))
        XCTAssertFalse(rendererSource.contains("float2 maskUV = u.maskStyle < -0.5 ? uv : in.uv;"))
    }

    func testLegacyPhosphorMaskHonorsItsConfiguredPitch() throws {
        let rendererSource = try rendererSource()

        XCTAssertTrue(rendererSource.contains("if (maskStyle < -0.5)"))
        XCTAssertTrue(rendererSource.contains("float3(1.0, 0.84, 0.84)"))
        XCTAssertTrue(
            rendererSource.contains(
                "floor(pixelPosition.x / max(pitch, 1.0))"
            )
        )
    }

    func testHalationRemainsAConditionalBoundedCostEffect() throws {
        let rendererSource = try rendererSource()
        let sampleCount = rendererSource.components(separatedBy: "source.sample").count - 1

        XCTAssertTrue(rendererSource.contains("if (u.halationStrength > 0.0001)"))
        XCTAssertLessThanOrEqual(sampleCount, 8, "Keep the real-time lens at eight texture taps or fewer.")
    }

    func testOuterMaskKeepsTheViewportBoundaryOpaque() throws {
        let rendererSource = try rendererSource()

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
        let rendererSource = try rendererSource()

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
