import AppKit
import CoreGraphics
import ScreenCaptureKit
import WindowCRTLensCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var lensController: LensController?
    private var selectedPreset: LensPreset = .glassy
    private let appearanceStore = LensAppearanceStore()
    private var appearance: LensAppearance = .default
    private var appearancePanelController: AppearancePanelController?
    private var presetItems: [LensPreset: NSMenuItem] = [:]
    private var targetItem: NSMenuItem!
    private var stopItem: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        DiagnosticLog.shared.record("app_launch", [
            "parentPID": getppid(),
            "bundlePath": Bundle.main.bundlePath,
            "executablePath": Bundle.main.executablePath ?? "unknown",
            "build": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "development",
            "os": ProcessInfo.processInfo.operatingSystemVersionString,
            "screenCapturePermission": CGPreflightScreenCaptureAccess(),
            "runningCopies": LensDiagnostics.runningCopies(),
        ])
        appearance = appearanceStore.load()
        buildStatusMenu()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
            DiagnosticLog.shared.record("picker_trigger", ["source": "launch"])
            self?.chooseWindow()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        lensController?.stop()
        DiagnosticLog.shared.record("app_terminate")
        DiagnosticLog.shared.flush()
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        DiagnosticLog.shared.record("app_reopen", ["hasVisibleWindows": flag])
        DispatchQueue.main.async { [weak self] in
            self?.chooseWindow()
        }
        return true
    }

    private func buildStatusMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.title = "◉"
        statusItem.button?.toolTip = "Window CRT Lens — isolated test"

        let menu = NSMenu()
        let heading = NSMenuItem(title: "Window CRT Lens", action: nil, keyEquivalent: "")
        heading.isEnabled = false
        menu.addItem(heading)

        targetItem = NSMenuItem(title: "No window selected", action: nil, keyEquivalent: "")
        targetItem.isEnabled = false
        menu.addItem(targetItem)
        menu.addItem(.separator())

        let select = NSMenuItem(title: "Choose Window…", action: #selector(chooseWindow), keyEquivalent: "w")
        select.target = self
        menu.addItem(select)

        stopItem = NSMenuItem(title: "Stop Lens", action: #selector(stopLens), keyEquivalent: ".")
        stopItem.target = self
        stopItem.isEnabled = false
        menu.addItem(stopItem)

        let presetMenu = NSMenu()
        for preset in LensPreset.allCases {
            let item = NSMenuItem(title: preset.displayName, action: #selector(selectPreset(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = preset.rawValue
            item.state = preset == selectedPreset ? .on : .off
            presetMenu.addItem(item)
            presetItems[preset] = item
        }
        let presetRoot = NSMenuItem(title: "Look", action: nil, keyEquivalent: "")
        presetRoot.submenu = presetMenu
        menu.addItem(presetRoot)

        let appearance = NSMenuItem(title: "CRT appearance…", action: #selector(showAppearanceSettings), keyEquivalent: ",")
        appearance.target = self
        menu.addItem(appearance)

        let diagnostics = NSMenu()
        let markBad = NSMenuItem(title: "Mark Mirror Glitch", action: #selector(markMirrorGlitch), keyEquivalent: "")
        markBad.target = self
        diagnostics.addItem(markBad)
        let markGood = NSMenuItem(title: "Mark Looks Normal", action: #selector(markLooksNormal), keyEquivalent: "")
        markGood.target = self
        diagnostics.addItem(markGood)
        let openLogs = NSMenuItem(title: "Open Logs", action: #selector(openDiagnosticLogs), keyEquivalent: "")
        openLogs.target = self
        diagnostics.addItem(openLogs)
        let diagnosticsRoot = NSMenuItem(title: "Diagnostics", action: nil, keyEquivalent: "")
        diagnosticsRoot.submenu = diagnostics
        menu.addItem(diagnosticsRoot)

        menu.addItem(.separator())
        let note = NSMenuItem(title: "Clicks and typing pass through to the real window", action: nil, keyEquivalent: "")
        note.isEnabled = false
        menu.addItem(note)

        let quit = NSMenuItem(title: "Quit Window CRT Lens", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        statusItem.menu = menu
    }

    @objc private func chooseWindow() {
        DiagnosticLog.shared.record("picker_requested", ["permission": CGPreflightScreenCaptureAccess()])
        if !CGPreflightScreenCaptureAccess() {
            guard CGRequestScreenCaptureAccess() else {
                presentScreenRecordingPermissionMessage()
                return
            }
        }

        Task {
            do {
                let windows = try await CaptureService.listEligibleWindows()
                DiagnosticLog.shared.record("picker_ready", ["eligibleWindowCount": windows.count])
                await presentPicker(windows: windows)
            } catch {
                await presentCaptureError(error)
            }
        }
    }

    private func presentPicker(windows: [SCWindow]) async {
        guard !windows.isEmpty else {
            presentMessage(
                title: "No windows are available yet",
                message: "If you just granted Screen Recording access, quit and reopen Window CRT Lens. Then keep the terminal window visible and choose it again."
            )
            return
        }

        NSApp.activate(ignoringOtherApps: true)
        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 460, height: 28), pullsDown: false)
        for window in windows {
            let app = window.owningApplication?.applicationName ?? "Application"
            let title = (window.title?.isEmpty == false) ? window.title! : "Untitled window"
            let visibility = window.isOnScreen ? "" : " — another Space or minimized"
            popup.addItem(withTitle: "\(app) — \(title)\(visibility)")
        }

        let alert = NSAlert()
        alert.messageText = "Choose the window to put behind the CRT glass"
        alert.informativeText = "The processed lens sits over the real window but cannot receive clicks or keyboard focus."
        alert.accessoryView = popup
        alert.addButton(withTitle: "Start Lens")
        alert.addButton(withTitle: "Cancel")

        guard alert.runModal() == .alertFirstButtonReturn else {
            DiagnosticLog.shared.record("picker_cancelled")
            return
        }
        let index = max(0, popup.indexOfSelectedItem)
        guard windows.indices.contains(index) else { return }
        await startLens(for: windows[index])
    }

    private func startLens(for window: SCWindow) async {
        DiagnosticLog.shared.record("target_selected", [
            "windowID": window.windowID,
            "targetPID": window.owningApplication?.processID ?? -1,
            "targetBundleID": window.owningApplication?.bundleIdentifier ?? "unknown",
            "onScreen": window.isOnScreen, "frame": LensDiagnostics.rect(window.frame),
            "runningCopies": LensDiagnostics.runningCopies(),
        ])
        lensController?.stop()
        do {
            let readyWindow = try await activateAndResolve(window)

            let controller = try LensController(
                window: readyWindow,
                preset: selectedPreset,
                appearance: appearance
            )
            try await controller.start()
            lensController = controller
            let app = readyWindow.owningApplication?.applicationName ?? "Application"
            let title = (readyWindow.title?.isEmpty == false) ? readyWindow.title! : "Untitled window"
            targetItem.title = "Lens: \(app) — \(title)"
            stopItem.isEnabled = true

        } catch {
            DiagnosticLog.shared.record("lens_start_failed", LensDiagnostics.error(error))
            presentMessage(title: "The lens could not start", message: error.localizedDescription)
        }
    }

    private func activateAndResolve(_ window: SCWindow) async throws -> SCWindow {
        guard let pid = window.owningApplication?.processID,
              let application = NSRunningApplication(processIdentifier: pid),
              application.activate(options: [.activateAllWindows]) else {
            throw CaptureService.CaptureError.activationFailed
        }

        for attempt in 0..<20 {
            if attempt > 0 {
                try await Task.sleep(for: .milliseconds(100))
            }
            if let visibleWindow = try await CaptureService.onScreenWindow(windowID: window.windowID),
               WindowSelectionReadiness.isReady(
                   isOnScreen: visibleWindow.isOnScreen,
                   targetProcessID: pid,
                   frontmostProcessID: NSWorkspace.shared.frontmostApplication?.processIdentifier
               ) {
                DiagnosticLog.shared.record("target_ready", ["attempt": attempt, "windowID": window.windowID,
                    "frame": LensDiagnostics.rect(visibleWindow.frame)])
                return visibleWindow
            }
        }

        throw CaptureService.CaptureError.windowDidNotBecomeVisible
    }

    @objc private func selectPreset(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let preset = LensPreset(rawValue: raw) else { return }
        selectedPreset = preset
        DiagnosticLog.shared.record("preset_changed", ["preset": preset.rawValue])
        lensController?.preset = preset
        for (candidate, item) in presetItems {
            item.state = candidate == preset ? .on : .off
        }
    }

    @objc private func showAppearanceSettings() {
        if appearancePanelController == nil {
            appearancePanelController = AppearancePanelController(appearance: appearance) { [weak self] updated in
                guard let self else { return }
                appearance = updated
                appearanceStore.save(updated)
                lensController?.appearance = updated
            }
        }
        appearancePanelController?.show(appearance: appearance)
    }

    @objc private func stopLens() {
        lensController?.stop()
        lensController = nil
        targetItem.title = "No window selected"
        stopItem.isEnabled = false
    }

    private func markDiagnosticState(_ state: String) {
        DiagnosticLog.shared.record("user_marker", ["state": state, "hasLens": lensController != nil,
            "runningCopies": LensDiagnostics.runningCopies()])
        lensController?.recordDiagnosticSnapshot(reason: state)
        DiagnosticLog.shared.flush()
        if let failure = DiagnosticLog.shared.failureReason {
            presentMessage(title: "The marker could not be saved", message: "Local logging failed: \(failure)")
        }
    }

    @objc private func markMirrorGlitch() { markDiagnosticState("mirror_glitch") }
    @objc private func markLooksNormal() { markDiagnosticState("looks_normal") }

    @objc private func openDiagnosticLogs() {
        DiagnosticLog.shared.flush()
        NSWorkspace.shared.open(DiagnosticLog.shared.directory)
    }

    private func presentCaptureError(_ error: Error) async {
        DiagnosticLog.shared.record("capture_error", LensDiagnostics.error(error))
        let alert = NSAlert()
        alert.messageText = "Screen Recording access is required"
        alert.informativeText = "Window CRT Lens only reads the onscreen rectangle occupied by the window you select. It does not record or save anything.\n\n\(error.localizedDescription)"
        alert.addButton(withTitle: "Open Privacy Settings")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    private func presentScreenRecordingPermissionMessage() {
        let alert = NSAlert()
        alert.messageText = "Window CRT Lens is running"
        alert.informativeText = "Turn on Window CRT Lens in Privacy & Security > Screen & System Audio Recording. macOS may ask you to quit and reopen it afterward. The app only reads the onscreen rectangle occupied by the window you select and never saves a recording."
        alert.addButton(withTitle: "Open Privacy Settings")
        alert.addButton(withTitle: "Not Now")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    private func presentMessage(title: String, message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
