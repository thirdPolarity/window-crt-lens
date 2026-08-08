import CoreGraphics
import XCTest
@testable import WindowCRTLensCore

final class WindowCandidatePolicyTests: XCTestCase {
    func testOnlyInteractiveThirdPartyWindowsAreEligible() {
        let valid = WindowCandidate(
            windowID: 7,
            ownerPID: 200,
            appName: "Cathodium",
            bundleIdentifier: "com.rey.cathodium",
            title: "Settings",
            frame: CGRect(x: 20, y: 20, width: 900, height: 700),
            isOnScreen: true
        )
        let ownWindow = WindowCandidate(
            windowID: 8,
            ownerPID: 100,
            appName: "Window CRT Lens",
            bundleIdentifier: "com.rey.window-crt-lens",
            title: "Menu",
            frame: CGRect(x: 20, y: 20, width: 300, height: 300),
            isOnScreen: true
        )
        let systemWindow = WindowCandidate(
            windowID: 9,
            ownerPID: 300,
            appName: "Dock",
            bundleIdentifier: "com.apple.dock",
            title: "Dock",
            frame: CGRect(x: 0, y: 0, width: 1_000, height: 80),
            isOnScreen: true
        )
        let tinyWindow = WindowCandidate(
            windowID: 10,
            ownerPID: 400,
            appName: "Helper",
            bundleIdentifier: "com.example.helper",
            title: "Helper",
            frame: CGRect(x: 0, y: 0, width: 80, height: 80),
            isOnScreen: true
        )

        let eligible = [valid, ownWindow, systemWindow, tinyWindow].filter {
            WindowCandidatePolicy.isEligible($0, excludingPID: 100)
        }

        XCTAssertEqual(eligible, [valid])
    }
}
