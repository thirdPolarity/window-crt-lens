import AppKit
import CoreMedia
import CoreVideo
import Metal
import ScreenCaptureKit
import WindowCRTLensCore

final class CaptureService: NSObject, SCStreamOutput, SCStreamDelegate {
    var onFrame: ((MetalSourceFrame) -> Void)?

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

    init(device: MTLDevice) {
        self.device = device
        super.init()
        CVMetalTextureCacheCreate(nil, nil, device, nil, &textureCache)
    }

    static func listEligibleWindows() async throws -> [SCWindow] {
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
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
            let left = "\($0.owningApplication?.applicationName ?? "") \($0.title ?? "")"
            let right = "\($1.owningApplication?.applicationName ?? "") \($1.title ?? "")"
            return left.localizedCaseInsensitiveCompare(right) == .orderedAscending
        }
    }

    func start(windowID: CGWindowID, targetFPS: Int = 60) async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
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
    }

    func stop() {
        guard let stream else { return }
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
              let texture = CVMetalTextureGetTexture(cvTexture) else { return }

        diagnosticsLock.lock()
        deliveredTextureCount += 1
        diagnosticsLock.unlock()
        onFrame?(MetalSourceFrame(texture: texture, lifetimeAnchor: cvTexture))
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
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
        guard ProcessInfo.processInfo.environment["WINDOW_CRT_DIAGNOSTICS"] == "1" else { return }
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        timer.schedule(deadline: .now() + 1, repeating: 1)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            diagnosticsLock.lock()
            let received = receivedFrameCount
            let valid = validFrameCount
            let imageBuffers = imageBufferCount
            let complete = completeFrameCount
            let idle = idleFrameCount
            let other = otherStatusCount
            let textures = deliveredTextureCount
            diagnosticsLock.unlock()
            NSLog(
                "[Window CRT Lens] frames received=%d valid=%d imageBuffers=%d complete=%d idle=%d other=%d textures=%d",
                received,
                valid,
                imageBuffers,
                complete,
                idle,
                other,
                textures
            )
        }
        diagnosticsTimer = timer
        timer.resume()
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

        var errorDescription: String? {
            switch self {
            case .windowDisappeared: "The selected window is no longer available."
            case .displayUnavailable: "The display containing the selected window is unavailable."
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
