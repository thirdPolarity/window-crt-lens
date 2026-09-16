import AppKit
import WindowCRTLensCore

enum LensDiagnostics {
    static func rect(_ rect: CGRect) -> [String: Double] {
        ["x": rect.minX, "y": rect.minY, "width": rect.width, "height": rect.height]
    }

    static func error(_ error: Error) -> [String: Any] {
        let error = error as NSError
        // Descriptions/userInfo can contain document names or URLs.
        return ["domain": error.domain, "code": error.code]
    }

    @MainActor
    static func runningCopies() -> [[String: Any]] {
        NSRunningApplication.runningApplications(withBundleIdentifier:
            Bundle.main.bundleIdentifier ?? "com.rey.window-crt-lens.test").map {
                ["pid": $0.processIdentifier, "bundlePath": $0.bundleURL?.path ?? "unknown"]
            }
    }
}
