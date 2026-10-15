import AppKit
import Combine
import SwiftUI

@MainActor
final class StatusItemController: NSObject {
    private static let itemWidth: CGFloat = 250

    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private let contentView: StatusItemContentView

    init(controller: AppController) {
        statusItem = NSStatusBar.system.statusItem(withLength: Self.itemWidth)
        contentView = StatusItemContentView(controller: controller)
        super.init()

        if let button = statusItem.button {
            button.title = ""
            button.image = nil
            button.target = self
            button.action = #selector(togglePopover)
            button.sendAction(on: [.leftMouseUp])
            button.toolTip = L10n.string("app.name")

            contentView.frame = button.bounds
            contentView.autoresizingMask = [.width, .height]
            button.addSubview(contentView)
        }

        let hostingController = NSHostingController(rootView: MenuBarView(controller: controller))
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = hostingController
        popover.contentSize = NSSize(width: 370, height: 390)
    }

    deinit {
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    @objc private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        guard let button = statusItem.button else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }
}

@MainActor
private final class StatusItemContentView: NSView {
    private let iconView = NSImageView()
    private let deviceLabel = NSTextField(labelWithString: "")
    private let formatLabel = NSTextField(labelWithString: "")
    private var cancellables: Set<AnyCancellable> = []
    private let controller: AppController

    override var isFlipped: Bool { true }

    init(controller: AppController) {
        self.controller = controller
        super.init(frame: .zero)

        iconView.imageScaling = .scaleProportionallyDown
        iconView.contentTintColor = .labelColor

        configureLabel(deviceLabel, font: .systemFont(ofSize: 9, weight: .semibold))
        configureLabel(formatLabel, font: .systemFont(ofSize: 10, weight: .medium))

        addSubview(iconView)
        addSubview(deviceLabel)
        addSubview(formatLabel)

        Publishers.CombineLatest3(controller.$devices, controller.$rules, controller.$isPaused)
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _, _ in self?.refresh() }
            .store(in: &cancellables)

        refresh()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func layout() {
        super.layout()
        let iconSize: CGFloat = 15
        let leading: CGFloat = 5
        let textLeading = leading + iconSize + 5
        let textWidth = max(0, bounds.width - textLeading - 5)
        let halfHeight = bounds.height / 2

        iconView.frame = NSRect(
            x: leading,
            y: (bounds.height - iconSize) / 2,
            width: iconSize,
            height: iconSize
        )
        deviceLabel.frame = NSRect(
            x: textLeading,
            y: max(0, halfHeight - 12),
            width: textWidth,
            height: 13
        )
        formatLabel.frame = NSRect(
            x: textLeading,
            y: halfHeight - 1,
            width: textWidth,
            height: 12
        )
    }

    private func configureLabel(_ label: NSTextField, font: NSFont) {
        label.font = font
        label.textColor = .labelColor
        label.lineBreakMode = .byTruncatingMiddle
        label.maximumNumberOfLines = 1
        label.cell?.usesSingleLineMode = true
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }

    private func refresh() {
        let presentation = StatusItemPresentation(controller: controller)
        deviceLabel.stringValue = presentation.deviceName
        formatLabel.stringValue = presentation.fixedFormat
        iconView.image = NSImage(
            systemSymbolName: presentation.iconName,
            accessibilityDescription: L10n.string("app.name")
        )
        setAccessibilityLabel("\(presentation.deviceName), \(presentation.fixedFormat)")
        needsLayout = true
    }
}

@MainActor
private struct StatusItemPresentation {
    let deviceName: String
    let fixedFormat: String
    let iconName: String

    init(controller: AppController) {
        deviceName = controller.defaultOutputDevice?.name ?? L10n.string("status_item.no_device")
        iconName = controller.isPaused ? "waveform.slash" : "waveform"

        guard let device = controller.defaultOutputDevice,
              let rule = controller.rule(uid: device.uid),
              let target = rule.targets.first else {
            fixedFormat = Self.withPausePrefix(
                L10n.string("status_item.no_fixed"),
                isPaused: controller.isPaused
            )
            return
        }

        var summary = L10n.format(
            "status_item.format",
            target.domain.title,
            target.choice.compactDescription
        )
        if rule.targets.count > 1 {
            summary = L10n.format("status_item.more", summary, rule.targets.count - 1)
        }
        if !rule.isEnabled {
            summary = L10n.format(
                "status_item.prefix",
                L10n.string("status_item.disabled"),
                summary
            )
        }
        fixedFormat = Self.withPausePrefix(summary, isPaused: controller.isPaused)
    }

    private static func withPausePrefix(_ value: String, isPaused: Bool) -> String {
        guard isPaused else { return value }
        return L10n.format(
            "status_item.prefix",
            L10n.string("status_item.paused"),
            value
        )
    }
}
