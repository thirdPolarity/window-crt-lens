import AppKit
import MetalKit
import ScreenCaptureKit
import WindowCRTLensCore

@MainActor
final class LensController {
    var preset: LensPreset {
        didSet { renderer.preset = preset }
    }
    var appearance: LensAppearance {
        didSet {
            renderer.appearance = appearance
            recordDiagnosticSnapshot(reason: "appearance_changed")
        }
    }

    private let targetWindowID: CGWindowID
    private let targetProcessID: pid_t?
    private let ownProcessID = ProcessInfo.processInfo.processIdentifier
    private let overlayWindow: PassiveOverlayWindow
    private let metalView: MTKView
    private let renderer: CRTRenderer
    private let captureService: CaptureService
    private var trackingTimer: Timer?
    private var captureUpdateTask: Task<Void, Never>?
    private var lastQuartzFrame: CGRect
    private var captureGeometryFrame: CGRect
    private var diagnosticVisibility = "initial"

    init(window: SCWindow, preset: LensPreset, appearance: LensAppearance) throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw LensError.metalUnavailable
        }
        self.targetWindowID = window.windowID
        self.targetProcessID = window.owningApplication?.processID
        self.lastQuartzFrame = window.frame
        self.captureGeometryFrame = window.frame
        self.preset = preset
        self.appearance = appearance

        let primaryHeight = CGDisplayBounds(CGMainDisplayID()).height
        let frame = WindowCoordinateMapper.appKitFrame(for: window.frame, primaryDisplayHeight: primaryHeight)
        let metalView = MTKView(frame: NSRect(origin: .zero, size: frame.size), device: device)
        metalView.colorPixelFormat = .bgra8Unorm
        metalView.clearColor = MTLClearColor(red: 0.006, green: 0.007, blue: 0.01, alpha: 0)
        metalView.preferredFramesPerSecond = 60
        metalView.enableSetNeedsDisplay = false
        metalView.isPaused = false
        metalView.wantsLayer = true
        metalView.layer?.isOpaque = false

        let renderer = try CRTRenderer(device: device, pixelFormat: metalView.colorPixelFormat)
        renderer.preset = preset
        renderer.appearance = appearance
        metalView.delegate = renderer

        let overlayWindow = PassiveOverlayWindow(
            contentRect: frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        OverlayContract.configure(overlayWindow)
        overlayWindow.contentView = metalView

        let captureService = CaptureService(device: device)
        captureService.onFrame = { [weak renderer] frame in
            renderer?.update(frame: frame)
        }

        self.metalView = metalView
        self.renderer = renderer
        self.overlayWindow = overlayWindow
        self.captureService = captureService
        recordDiagnosticSnapshot(reason: "lens_created")
    }

    func start() async throws {
        try await captureService.start(windowID: targetWindowID)
        trackingTimer = Timer.scheduledTimer(withTimeInterval: 0.10, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.trackTargetWindow() }
        }
        trackTargetWindow()
    }

    func stop() {
        recordDiagnosticSnapshot(reason: "lens_stop")
        trackingTimer?.invalidate()
        trackingTimer = nil
        captureUpdateTask?.cancel()
        captureUpdateTask = nil
        captureService.stop()
        overlayWindow.orderOut(nil)
    }

    func recordDiagnosticSnapshot(reason: String) {
        DiagnosticLog.shared.record("lens_snapshot", [
            "captureID": captureService.diagnosticID, "reason": reason,
            "targetWindowID": targetWindowID, "targetPID": targetProcessID ?? -1,
            "overlayWindowID": overlayWindow.windowNumber, "overlayVisible": overlayWindow.isVisible,
            "frontmostPID": NSWorkspace.shared.frontmostApplication?.processIdentifier ?? -1,
            "targetFrame": LensDiagnostics.rect(lastQuartzFrame),
            "captureFrame": LensDiagnostics.rect(captureGeometryFrame),
            "overlayFrame": LensDiagnostics.rect(overlayWindow.frame),
            "preset": preset.rawValue, "zoom": appearance.zoom,
            "screenRadius": appearance.screenCornerRadius, "shellRadius": appearance.shellCornerRadius,
            "edgeSoftness": appearance.edgeSoftness,
        ])
        captureService.recordDiagnosticSnapshot(reason: reason)
    }

    private func recordVisibility(_ reason: String) {
        guard diagnosticVisibility != reason else { return }
        diagnosticVisibility = reason
        recordDiagnosticSnapshot(reason: reason)
    }

    private func trackTargetWindow() {
        let list = CGWindowListCopyWindowInfo(.optionIncludingWindow, targetWindowID) as? [[String: Any]] ?? []
        guard let info = list.first,
              let bounds = info[kCGWindowBounds as String] as? [String: CGFloat],
              let x = bounds["X"], let y = bounds["Y"],
              let width = bounds["Width"], let height = bounds["Height"] else {
            recordVisibility("target_missing")
            overlayWindow.orderOut(nil)
            return
        }

        let isOnScreen = (info[kCGWindowIsOnscreen as String] as? Bool) ?? true
        guard isOnScreen else {
            recordVisibility("target_offscreen")
            overlayWindow.orderOut(nil)
            return
        }

        if let targetProcessID,
           !LensVisibilityPolicy.shouldShow(
               targetProcessID: targetProcessID,
               ownProcessID: ownProcessID,
               frontmostProcessID: NSWorkspace.shared.frontmostApplication?.processIdentifier
           ) {
            recordVisibility("other_app_foreground")
            overlayWindow.orderOut(nil)
            return
        }

        let quartzFrame = CGRect(x: x, y: y, width: width, height: height)
        if quartzFrame != lastQuartzFrame {
            DiagnosticLog.shared.record("target_geometry_changed", ["captureID": captureService.diagnosticID,
                "frame": LensDiagnostics.rect(quartzFrame)])
            lastQuartzFrame = quartzFrame
            let primaryHeight = CGDisplayBounds(CGMainDisplayID()).height
            let appKitFrame = WindowCoordinateMapper.appKitFrame(for: quartzFrame, primaryDisplayHeight: primaryHeight)
            overlayWindow.setFrame(appKitFrame, display: false)
            metalView.frame = NSRect(origin: .zero, size: appKitFrame.size)
            captureUpdateTask?.cancel()
            captureUpdateTask = Task { [weak self] in
                do {
                    try await Task.sleep(for: .milliseconds(120))
                    guard !Task.isCancelled, let self else { return }
                    try await captureService.update(windowFrame: quartzFrame)
                    captureGeometryFrame = quartzFrame
                    trackTargetWindow()
                } catch is CancellationError {
                    return
                } catch {
                    DiagnosticLog.shared.record("geometry_update_failed", LensDiagnostics.error(error))
                    NSLog("[Window CRT Lens] capture geometry update failed: %@", error.localizedDescription)
                }
            }
        }

        guard LensGeometryTransitionPolicy.isReady(
            captureFrame: captureGeometryFrame,
            targetFrame: quartzFrame
        ) else {
            recordVisibility("waiting_for_geometry")
            overlayWindow.orderOut(nil)
            return
        }
        overlayWindow.orderFrontRegardless()
        recordVisibility("overlay_visible")
    }

    enum LensError: LocalizedError {
        case metalUnavailable

        var errorDescription: String? {
            "Metal is not available on this Mac."
        }
    }
}
