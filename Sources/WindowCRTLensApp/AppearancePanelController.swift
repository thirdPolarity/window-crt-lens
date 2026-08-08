import AppKit
import WindowCRTLensCore

@MainActor
final class AppearancePanelController: NSWindowController {
    private let onChange: (LensAppearance) -> Void
    private let zoomSlider: NSSlider
    private let screenSlider: NSSlider
    private let shellSlider: NSSlider
    private let softnessSlider: NSSlider
    private let zoomValue = NSTextField(labelWithString: "")
    private let screenValue = NSTextField(labelWithString: "")
    private let shellValue = NSTextField(labelWithString: "")
    private let softnessValue = NSTextField(labelWithString: "")

    init(appearance: LensAppearance, onChange: @escaping (LensAppearance) -> Void) {
        self.onChange = onChange
        self.zoomSlider = Self.makeSlider(range: LensAppearance.zoomRange, value: appearance.zoom)
        self.screenSlider = Self.makeSlider(range: LensAppearance.screenCornerRange, value: appearance.screenCornerRadius)
        self.shellSlider = Self.makeSlider(range: LensAppearance.shellCornerRange, value: appearance.shellCornerRadius)
        self.softnessSlider = Self.makeSlider(range: LensAppearance.edgeSoftnessRange, value: appearance.edgeSoftness)

        let panel = AppearancePanel(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 435),
            styleMask: [.titled, .closable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = "CRT appearance"
        panel.isFloatingPanel = true
        panel.level = OverlayContract.settingsPanelLevel
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        super.init(window: panel)

        zoomSlider.target = self
        zoomSlider.action = #selector(sliderChanged(_:))
        zoomSlider.tag = 0
        zoomSlider.setAccessibilityLabel("CRT zoom")
        screenSlider.target = self
        screenSlider.action = #selector(sliderChanged(_:))
        screenSlider.tag = 1
        screenSlider.setAccessibilityLabel("Screen corner radius")
        shellSlider.target = self
        shellSlider.action = #selector(sliderChanged(_:))
        shellSlider.tag = 2
        shellSlider.setAccessibilityLabel("Lens shell corner radius")
        softnessSlider.target = self
        softnessSlider.action = #selector(sliderChanged(_:))
        softnessSlider.tag = 3
        softnessSlider.setAccessibilityLabel("Edge smoothing")

        configureValueLabel(zoomValue)
        configureValueLabel(screenValue)
        configureValueLabel(shellValue)
        configureValueLabel(softnessValue)
        panel.contentView = buildContentView()
        updateValueLabels()
    }

    required init?(coder: NSCoder) {
        nil
    }

    func show(appearance: LensAppearance) {
        zoomSlider.doubleValue = appearance.zoom
        screenSlider.doubleValue = appearance.screenCornerRadius
        shellSlider.doubleValue = appearance.shellCornerRadius
        softnessSlider.doubleValue = appearance.edgeSoftness
        updateValueLabels()
        showWindow(nil)
        window?.center()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    @objc private func sliderChanged(_ sender: NSSlider) {
        updateValueLabels()
        onChange(currentAppearance)
    }

    @objc private func resetAppearance() {
        let defaults = LensAppearance.default
        zoomSlider.doubleValue = defaults.zoom
        screenSlider.doubleValue = defaults.screenCornerRadius
        shellSlider.doubleValue = defaults.shellCornerRadius
        softnessSlider.doubleValue = defaults.edgeSoftness
        updateValueLabels()
        onChange(defaults)
    }

    @objc private func closePanel() {
        close()
    }

    private var currentAppearance: LensAppearance {
        LensAppearance(
            screenCornerRadius: screenSlider.doubleValue,
            shellCornerRadius: shellSlider.doubleValue,
            edgeSoftness: softnessSlider.doubleValue,
            zoom: zoomSlider.doubleValue
        )
    }

    private func buildContentView() -> NSView {
        let content = NSView()

        let title = NSTextField(labelWithString: "Shape the glass")
        title.font = .systemFont(ofSize: 20, weight: .semibold)
        title.textColor = .labelColor

        let subtitle = NSTextField(wrappingLabelWithString: "Scale the image into the glass, round both boundaries independently, and smooth their edges without blurring terminal text.")
        subtitle.font = .systemFont(ofSize: 13)
        subtitle.textColor = .secondaryLabelColor

        let header = NSStackView(views: [title, subtitle])
        header.orientation = .vertical
        header.alignment = .leading
        header.spacing = 6

        let controls = NSStackView(views: [
            makeControlRow(
                title: "CRT zoom",
                detail: "Enlarges the image inside the curved glass.",
                slider: zoomSlider,
                valueLabel: zoomValue
            ),
            makeControlRow(
                title: "Screen corners",
                detail: "Hides desktop pixels at window corners.",
                slider: screenSlider,
                valueLabel: screenValue
            ),
            makeControlRow(
                title: "Lens shell corners",
                detail: "Rounds the outer CRT silhouette.",
                slider: shellSlider,
                valueLabel: shellValue
            ),
            makeControlRow(
                title: "Edge smoothing",
                detail: "Smooths the mask, not terminal text.",
                slider: softnessSlider,
                valueLabel: softnessValue
            ),
        ])
        controls.orientation = .vertical
        controls.alignment = .leading
        controls.spacing = 16

        let reset = NSButton(title: "Reset", target: self, action: #selector(resetAppearance))
        reset.bezelStyle = .rounded
        reset.setAccessibilityHelp("Restore the default zoom, screen, shell, and smoothing values")

        let done = NSButton(title: "Done", target: self, action: #selector(closePanel))
        done.bezelStyle = .rounded
        done.keyEquivalent = "\r"

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let footer = NSStackView(views: [reset, spacer, done])
        footer.orientation = .horizontal
        footer.alignment = .centerY
        footer.spacing = 10

        let stack = NSStackView(views: [header, controls, footer])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 24
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 26),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -26),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -22),
            header.widthAnchor.constraint(equalTo: stack.widthAnchor),
            controls.widthAnchor.constraint(equalTo: stack.widthAnchor),
            footer.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
        return content
    }

    private func makeControlRow(
        title: String,
        detail: String,
        slider: NSSlider,
        valueLabel: NSTextField
    ) -> NSView {
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 13, weight: .medium)
        titleLabel.textColor = .labelColor

        let detailLabel = NSTextField(labelWithString: detail)
        detailLabel.font = .systemFont(ofSize: 11)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.lineBreakMode = .byTruncatingTail

        let labels = NSStackView(views: [titleLabel, detailLabel])
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 3

        let row = NSStackView(views: [labels, slider, valueLabel])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        NSLayoutConstraint.activate([
            labels.widthAnchor.constraint(equalToConstant: 222),
            slider.widthAnchor.constraint(equalToConstant: 188),
            valueLabel.widthAnchor.constraint(equalToConstant: 56),
        ])
        return row
    }

    private func updateValueLabels() {
        zoomValue.stringValue = String(format: "%.2f×", zoomSlider.doubleValue)
        screenValue.stringValue = "\(Int(screenSlider.doubleValue.rounded())) pt"
        shellValue.stringValue = "\(Int(shellSlider.doubleValue.rounded())) pt"
        softnessValue.stringValue = String(format: "%.2f px", softnessSlider.doubleValue)
    }

    private func configureValueLabel(_ label: NSTextField) {
        label.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.alignment = .right
    }

    private static func makeSlider(range: ClosedRange<Double>, value: Double) -> NSSlider {
        let slider = NSSlider(
            value: value,
            minValue: range.lowerBound,
            maxValue: range.upperBound,
            target: nil,
            action: nil
        )
        slider.isContinuous = true
        slider.controlSize = .large
        return slider
    }
}

private final class AppearancePanel: NSPanel {
    override func cancelOperation(_ sender: Any?) {
        close()
    }
}
