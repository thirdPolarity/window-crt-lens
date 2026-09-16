import AppKit
import CoreMedia
import CoreVideo
import Metal
import ScreenCaptureKit
import WindowCRTLensCore

final class CaptureService: NSObject, SCStreamOutput, SCStreamDelegate {
    var onFrame: ((MetalSourceFrame) -> Void)?
    let diagnosticID = UUID().uuidString

    private let device: MTLDevice
    private var textureCache: CVMetalTextureCache?
    private var stream: SCStream?
    private var availableDisplays: [SCDisplay] = []
    private var excludedApplications: [SCRunningApplication] = []
    private var captureDisplay: SCDisplay?
    private var targetFPS = 60
    private let diagnosticsLock = NSLock()
    private var diagnosticsTimer: DispatchSourceTimer?
    private var receivedFrameCount = 0
    private var validFrameCount = 0
    private var imageBufferCount = 0
    private var completeFrameCount = 0
    private var idleFrameCount = 0
    private var otherStatusCount = 0
    private var deliveredTextureCount = 0
    private var lastFrameUptime: TimeInterval?
    private var lastTextureUptime: TimeInterval?
    private var latestWidth = 0
    private var latestHeight = 0
    private var latestStatus = -1
    private var statusCounts: [String: Int] = [:]
    private var textureFailureCount = 0
    private var latestTextureError = 0

    init(device: MTLDevice) {
        self.device = device
        super.init()
        CVMetalTextureCacheCreate(nil, nil, device, nil, &textureCache)
    }

    static func listEligibleWindows() async throws -> [SCWindow] {
        // Query every Space. Restricting this snapshot to the current Space makes a
        // valid target disappear whenever opening the menu changes macOS focus.
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
        let ownPID = ProcessInfo.processInfo.processIdentifier

        return content.windows.filter { window in
            guard let owner = window.owningApplication else { return false }
            let candidate = WindowCandidate(
                windowID: window.windowID,
                ownerPID: owner.processID,
                appName: owner.applicationName,
                bundleIdentifier: owner.bundleIdentifier,
                title: window.title ?? "",
                frame: window.frame,
                isOnScreen: window.isOnScreen
            )
            return WindowCandidatePolicy.isEligible(candidate, excludingPID: ownPID)
        }.sorted {
            if $0.isOnScreen != $1.isOnScreen {
                return $0.isOnScreen
            }
            let left = "\($0.owningApplication?.applicationName ?? "") \($0.title ?? "")"
            let right = "\($1.owningApplication?.applicationName ?? "") \($1.title ?? "")"
            return left.localizedCaseInsensitiveCompare(right) == .orderedAscending
        }
    }

    static func onScreenWindow(windowID: CGWindowID) async throws -> SCWindow? {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        return content.windows.first(where: { $0.windowID == windowID })
    }

    func start(windowID: CGWindowID, targetFPS: Int = 60) async throws {
        DiagnosticLog.shared.record("capture_start_requested", ["captureID": diagnosticID, "windowID": windowID])
        // The picker is closed and our overlay is not yet visible. An onscreen-only
        // snapshot can omit this app entirely, creating an empty exclusion filter
        // that feeds the CRT overlay back into its own capture.
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        guard let window = content.windows.first(where: { $0.windowID == windowID }) else {
            throw CaptureError.windowDisappeared
        }
        guard let display = Self.preferredDisplay(for: window.frame, in: content.displays) else {
            throw CaptureError.displayUnavailable
        }

        let scale = await MainActor.run { Self.backingScale(for: window.frame) }
        let configuration = Self.configuration(
            for: window.frame,
            on: display,
            scale: scale,
            targetFPS: targetFPS
        )
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let excludedApplications = content.applications.filter { $0.processID == ownPID }
        guard !excludedApplications.isEmpty else {
            DiagnosticLog.shared.record("capture_blocked_missing_self_exclusion", ["captureID": diagnosticID, "ownPID": ownPID])
            throw CaptureError.selfExclusionUnavailable
        }
        DiagnosticLog.shared.record("capture_filter_created", [
            "captureID": diagnosticID, "ownPID": ownPID,
            "excludedPIDs": excludedApplications.map(\.processID),
            "selfExcluded": excludedApplications.contains { $0.processID == ownPID },
            "ownWindowsInSnapshot": content.windows.filter { $0.owningApplication?.processID == ownPID }.map(\.windowID),
            "displayID": display.displayID, "displayFrame": LensDiagnostics.rect(display.frame),
            "targetFrame": LensDiagnostics.rect(window.frame),
            "sourceRect": LensDiagnostics.rect(configuration.sourceRect),
            "width": configuration.width, "height": configuration.height, "scale": scale,
            "displayCount": content.displays.count, "mode": "display_excluding_applications",
        ])
        let filter = SCContentFilter(
            display: display,
            excludingApplications: excludedApplications,
            exceptingWindows: []
        )
        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: .global(qos: .userInteractive))
        try await stream.startCapture()
        self.stream = stream
        self.availableDisplays = content.displays
        self.excludedApplications = excludedApplications
        self.captureDisplay = display
        self.targetFPS = targetFPS
        DiagnosticLog.shared.record("capture_started", ["captureID": diagnosticID])
        startDiagnostics()
    }

    func update(windowFrame: CGRect) async throws {
        guard let stream,
              let display = Self.preferredDisplay(for: windowFrame, in: availableDisplays) else { return }

        let scale = await MainActor.run { Self.backingScale(for: windowFrame) }
        let configuration = Self.configuration(
            for: windowFrame,
            on: display,
            scale: scale,
            targetFPS: targetFPS
        )

        DiagnosticLog.shared.record("capture_update_requested", ["captureID": diagnosticID,
            "displayID": display.displayID, "previousDisplayID": captureDisplay?.displayID ?? 0,
            "targetFrame": LensDiagnostics.rect(windowFrame), "sourceRect": LensDiagnostics.rect(configuration.sourceRect),
            "width": configuration.width, "height": configuration.height, "taskCancelled": Task.isCancelled])

        if captureDisplay?.displayID != display.displayID {
            let filter = SCContentFilter(
                display: display,
                excludingApplications: excludedApplications,
                exceptingWindows: []
            )
            try await stream.updateContentFilter(filter)
            captureDisplay = display
        }
        try await stream.updateConfiguration(configuration)
        DiagnosticLog.shared.record("capture_update_completed", ["captureID": diagnosticID,
            "targetFrame": LensDiagnostics.rect(windowFrame), "taskCancelled": Task.isCancelled])
    }

    func stop() {
        guard let stream else { return }
        recordDiagnosticSnapshot(reason: "capture_stop")
        self.stream = nil
        diagnosticsTimer?.cancel()
        diagnosticsTimer = nil
        availableDisplays = []
        excludedApplications = []
        captureDisplay = nil
        Task { try? await stream.stopCapture() }
    }

    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        recordFrame(sampleBuffer, type: type)
        guard type == .screen,
              let pixelBuffer = sampleBuffer.imageBuffer,
              let textureCache else { return }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        var cvTexture: CVMetalTexture?
        let result = CVMetalTextureCacheCreateTextureFromImage(
            nil,
            textureCache,
            pixelBuffer,
            nil,
            .bgra8Unorm,
            width,
            height,
            0,
            &cvTexture
        )
        guard result == kCVReturnSuccess,
              let cvTexture,
              let texture = CVMetalTextureGetTexture(cvTexture) else {
            diagnosticsLock.lock()
            textureFailureCount += 1
            latestTextureError = Int(result)
            diagnosticsLock.unlock()
            return
        }

        diagnosticsLock.lock()
        deliveredTextureCount += 1
        lastTextureUptime = ProcessInfo.processInfo.systemUptime
        let isFirstTexture = deliveredTextureCount == 1
        diagnosticsLock.unlock()
        if isFirstTexture {
            DiagnosticLog.shared.record("first_texture", ["captureID": diagnosticID, "width": width, "height": height])
        }
        onFrame?(MetalSourceFrame(texture: texture, lifetimeAnchor: cvTexture))
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        var details = LensDiagnostics.error(error)
        details["captureID"] = diagnosticID
        DiagnosticLog.shared.record("capture_stopped_with_error", details)
        recordDiagnosticSnapshot(reason: "stream_error")
        NSLog("[Window CRT Lens] capture stopped: %@", error.localizedDescription)
    }

    private func recordFrame(_ sampleBuffer: CMSampleBuffer, type: SCStreamOutputType) {
        guard type == .screen else { return }

        var status: SCFrameStatus?
        if let attachmentsArray = CMSampleBufferGetSampleAttachmentsArray(
            sampleBuffer,
            createIfNecessary: false
        ) as? [[SCStreamFrameInfo: Any]],
           let statusRawValue = attachmentsArray.first?[.status] as? Int {
            status = SCFrameStatus(rawValue: statusRawValue)
        }

        diagnosticsLock.lock()
        lastFrameUptime = ProcessInfo.processInfo.systemUptime
        latestStatus = status?.rawValue ?? -1
        statusCounts[String(latestStatus), default: 0] += 1
        if let image = sampleBuffer.imageBuffer {
            latestWidth = CVPixelBufferGetWidth(image)
            latestHeight = CVPixelBufferGetHeight(image)
        }
        receivedFrameCount += 1
        if sampleBuffer.isValid { validFrameCount += 1 }
        if sampleBuffer.imageBuffer != nil { imageBufferCount += 1 }
        switch status {
        case .complete:
            completeFrameCount += 1
        case .idle:
            idleFrameCount += 1
        default:
            otherStatusCount += 1
        }
        diagnosticsLock.unlock()
    }

    private func startDiagnostics() {
        diagnosticsTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        timer.schedule(deadline: .now() + 1, repeating: 5)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            recordDiagnosticSnapshot(reason: "heartbeat")
        }
        diagnosticsTimer = timer
        timer.resume()
    }

    func recordDiagnosticSnapshot(reason: String) {
        diagnosticsLock.lock()
        let now = ProcessInfo.processInfo.systemUptime
        let details: [String: Any] = [
            "captureID": diagnosticID, "reason": reason,
            "received": receivedFrameCount, "valid": validFrameCount, "imageBuffers": imageBufferCount,
            "complete": completeFrameCount, "idle": idleFrameCount, "otherStatus": otherStatusCount,
            "textures": deliveredTextureCount, "textureFailures": textureFailureCount,
            "lastTextureError": latestTextureError, "lastStatus": latestStatus, "statusCounts": statusCounts,
            "width": latestWidth, "height": latestHeight,
            "secondsSinceFrame": lastFrameUptime.map { now - $0 } ?? -1,
            "secondsSinceTexture": lastTextureUptime.map { now - $0 } ?? -1,
        ]
        diagnosticsLock.unlock()
        DiagnosticLog.shared.record("capture_health", details)
    }

    private static func preferredDisplay(for windowFrame: CGRect, in displays: [SCDisplay]) -> SCDisplay? {
        displays.max {
            $0.frame.intersection(windowFrame).area < $1.frame.intersection(windowFrame).area
        }
    }

    private static func configuration(
        for windowFrame: CGRect,
        on display: SCDisplay,
        scale: CGFloat,
        targetFPS: Int
    ) -> SCStreamConfiguration {
        var width = max(Int(windowFrame.width * scale), 320)
        var height = max(Int(windowFrame.height * scale), 240)
        let cap = min(1.0, min(2_560.0 / Double(width), 1_800.0 / Double(height)))
        width = max(Int(Double(width) * cap), 320)
        height = max(Int(Double(height) * cap), 240)

        let configuration = SCStreamConfiguration()
        configuration.width = width
        configuration.height = height
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(targetFPS))
        configuration.queueDepth = 3
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.showsCursor = false
        configuration.capturesAudio = false
        configuration.sourceRect = CGRect(
            x: windowFrame.minX - display.frame.minX,
            y: windowFrame.minY - display.frame.minY,
            width: windowFrame.width,
            height: windowFrame.height
        )
        return configuration
    }

    @MainActor
    private static func backingScale(for quartzFrame: CGRect) -> CGFloat {
        let midpoint = CGPoint(x: quartzFrame.midX, y: quartzFrame.midY)
        for screen in NSScreen.screens {
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else { continue }
            if CGDisplayBounds(number).contains(midpoint) {
                return max(screen.backingScaleFactor, 1)
            }
        }
        return max(NSScreen.main?.backingScaleFactor ?? 1, 1)
    }

    enum CaptureError: LocalizedError {
        case windowDisappeared
        case displayUnavailable
        case activationFailed
        case windowDidNotBecomeVisible
        case selfExclusionUnavailable

        var errorDescription: String? {
            switch self {
            case .windowDisappeared: "The selected window is no longer available."
            case .displayUnavailable: "The display containing the selected window is unavailable."
            case .activationFailed: "macOS could not bring the selected application forward."
            case .windowDidNotBecomeVisible: "The selected window did not become visible. Restore it from the Dock and choose it again."
            case .selfExclusionUnavailable: "macOS could not exclude the CRT lens from capture. The lens was stopped to prevent a mirror loop. Choose the window again."
            }
        }
    }
}

private extension CGRect {
    var area: CGFloat {
        guard !isNull, !isInfinite else { return 0 }
        return max(width, 0) * max(height, 0)
    }
}
