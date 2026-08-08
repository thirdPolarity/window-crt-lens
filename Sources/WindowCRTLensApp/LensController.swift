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
        didSet { renderer.appearance = appearance }
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

    init(window: SCWindow, preset: LensPreset, appearance: LensAppearance) throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw LensError.metalUnavailable
        }
        self.targetWindowID = window.windowID
        self.targetProcessID = window.owningApplication?.processID
        self.lastQuartzFrame = window.frame
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
    }

    func start() async throws {
        try await captureService.start(windowID: targetWindowID)
        trackingTimer = Timer.scheduledTimer(withTimeInterval: 0.10, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.trackTargetWindow() }
        }
        trackTargetWindow()
    }

    func stop() {
        trackingTimer?.invalidate()
        trackingTimer = nil
        captureUpdateTask?.cancel()
        captureUpdateTask = nil
        captureService.stop()
        overlayWindow.orderOut(nil)
    }

    private func trackTargetWindow() {
        let list = CGWindowListCopyWindowInfo(.optionIncludingWindow, targetWindowID) as? [[String: Any]] ?? []
        guard let info = list.first,
              let bounds = info[kCGWindowBounds as String] as? [String: CGFloat],
              let x = bounds["X"], let y = bounds["Y"],
              let width = bounds["Width"], let height = bounds["Height"] else {
            overlayWindow.orderOut(nil)
            return
        }

        let isOnScreen = (info[kCGWindowIsOnscreen as String] as? Bool) ?? true
        guard isOnScreen else {
            overlayWindow.orderOut(nil)
            return
        }

        if let targetProcessID,
           !LensVisibilityPolicy.shouldShow(
               targetProcessID: targetProcessID,
               ownProcessID: ownProcessID,
               frontmostProcessID: NSWorkspace.shared.frontmostApplication?.processIdentifier
           ) {
            overlayWindow.orderOut(nil)
            return
        }

        let quartzFrame = CGRect(x: x, y: y, width: width, height: height)
        if quartzFrame != lastQuartzFrame {
            lastQuartzFrame = quartzFrame
            let primaryHeight = CGDisplayBounds(CGMainDisplayID()).height
            let appKitFrame = WindowCoordinateMapper.appKitFrame(for: quartzFrame, primaryDisplayHeight: primaryHeight)
            overlayWindow.setFrame(appKitFrame, display: false)
            metalView.frame = NSRect(origin: .zero, size: appKitFrame.size)
            captureUpdateTask?.cancel()
            captureUpdateTask = Task { [weak captureService] in
                try? await Task.sleep(for: .milliseconds(120))
                guard !Task.isCancelled else { return }
                try? await captureService?.update(windowFrame: quartzFrame)
            }
        }
        overlayWindow.orderFrontRegardless()
    }

    enum LensError: LocalizedError {
        case metalUnavailable

        var errorDescription: String? {
            "Metal is not available on this Mac."
        }
    }
}
